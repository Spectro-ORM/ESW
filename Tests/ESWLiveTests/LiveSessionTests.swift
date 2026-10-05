import ESWLive
import Testing

private struct Counter: LiveView {
    func mount(_ context: LiveContext) async throws -> Int { context.isConnected ? 1 : 0 }
    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        if event.name == "fail" { throw LiveError.invalidEvent }
        try await Task.sleep(for: .milliseconds(2))
        return event.name == "noop" ? state : state + 1
    }
    func render(_ state: Int) -> ESWLiveRender { #live("<p>{state}</p>") }
}

private actor Signal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func fire() {
        fired = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

private struct SuspendedView: LiveView {
    let started: Signal
    let release: Signal
    var suspendMount = false
    func mount(_ context: LiveContext) async throws -> Int {
        if suspendMount { await started.fire(); await release.wait() }
        return 0
    }
    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        await started.fire()
        await release.wait()
        return state + 1
    }
    func render(_ state: Int) -> ESWLiveRender { #live("<p>{state}</p>") }
}

@Suite("Live session lifecycle")
struct LiveSessionTests {
    @Test func failedHandlersAreNotRepeatedOnRetryOrAfterEviction() async throws {
        let session = try await LiveSession(view: Counter())
        _ = try await session.connect()
        let rejected = LiveEvent(id: "failed", name: "fail", baseRevision: 1)
        await #expect(throws: LiveError.invalidEvent) { try await session.handle(rejected) }
        await #expect(throws: LiveError.invalidEvent) { try await session.handle(rejected) }
        #expect(try await session.connect().revision == 2)
        for _ in 0..<128 {
            await #expect(throws: LiveError.invalidEvent) { try await session.handle(.init(name: "fail")) }
        }
        await #expect(throws: LiveError.stale) { try await session.handle(rejected) }
        #expect(await session.html == "<p>1</p>")
    }

    @Test(arguments: [false, true])
    func pendingMountCannotOutliveInvalidation(shutdown: Bool) async throws {
        let started = Signal(), release = Signal()
        let host = LiveHost(SuspendedView(started: started, release: release, suspendMount: true), capacity: 1)
        let mount = Task { try await host.mount(owner: "alice") }
        await started.wait()
        if shutdown { await host.shutdown() } else { await host.invalidate(owner: "alice") }
        await release.fire()
        await #expect(throws: LiveError.closed) { try await mount.value }
        #expect(await host.count == 0)
        if shutdown {
            await #expect(throws: LiveError.closed) { try await host.mount(owner: "alice") }
        } else {
            _ = try await host.mount(owner: "alice")
            #expect(await host.count == 1)
            await host.shutdown()
        }
    }

    @Test func queueIsBoundedAndClosingPreventsSuspendedCommit() async throws {
        let started = Signal(), release = Signal()
        let session = try await LiveSession(view: SuspendedView(started: started, release: release), queueLimit: 1)
        _ = try await session.connect()
        let event = Task { try await session.handle(.init(name: "increment")) }
        await started.wait()
        await #expect(throws: LiveError.busy) { try await session.handle(.init(name: "increment")) }
        await session.close()
        await release.fire()
        await #expect(throws: CancellationError.self) { try await event.value }
        #expect(await session.html == "<p>0</p>")
        await #expect(throws: LiveError.closed) { try await session.handle(.init(name: "increment")) }
    }

    @Test func requestCancellationRetainsAcceptedEventForRetry() async throws {
        let started = Signal(), release = Signal()
        let session = try await LiveSession(view: SuspendedView(started: started, release: release))
        _ = try await session.connect()
        let event = LiveEvent(id: "disconnected", name: "increment", baseRevision: 1)
        let request = Task { try await session.handle(event) }
        await started.wait()
        request.cancel()
        await release.fire()
        let committed = try await request.value
        #expect(try await session.handle(event) == committed)
        #expect(await session.html == "<p>1</p>")
    }

    @Test func staleRetriesCannotExecuteAfterReplyCacheEviction() async throws {
        let session = try await LiveSession(view: Counter())
        _ = try await session.connect()
        let original = LiveEvent(id: "old", name: "increment", baseRevision: 1)
        _ = try await session.handle(original)
        for _ in 0..<128 { _ = try await session.handle(.init(name: "increment")) }
        await #expect(throws: LiveError.stale) { try await session.handle(original) }
        #expect(await session.html == "<p>130</p>")
    }

    @Test func malformedPayloadDoesNotReachTheHandler() async throws {
        let session = try await LiveSession(view: Counter())
        _ = try await session.connect()
        await #expect(throws: LiveError.invalidEvent) { try await session.handle(.init(name: "")) }
        await #expect(throws: LiveError.invalidEvent) {
            try await session.handle(.init(name: "increment", values: ["big": [String(repeating: "x", count: 65_537)]]))
        }
        #expect(await session.html == "<p>1</p>")
    }

    @Test func streamReplacementAndOwnerInvalidation() async throws {
        let host = LiveHost(Counter())
        let mount = try await host.mount(owner: "alice")
        var old = try await host.subscribe(mount.id, owner: "alice").makeAsyncIterator()
        _ = await old.next()
        var new = try await host.subscribe(mount.id, owner: "alice").makeAsyncIterator()
        _ = await new.next()
        #expect(await old.next() == nil)
        _ = try await host.send(mount.id, event: .init(name: "increment"))
        #expect(await new.next()?.revision == 2)
        await host.invalidate(owner: "alice")
        #expect(await new.next() == nil)
        #expect(await host.count == 0)
    }

    @Test func sessionLifetimeEndsItsStream() async throws {
        let host = LiveHost(Counter(), lifetime: .milliseconds(40))
        let mount = try await host.mount(owner: "alice")
        var stream = try await host.subscribe(mount.id, owner: "alice").makeAsyncIterator()
        _ = await stream.next()
        #expect(await stream.next() == nil)
        #expect(await host.count == 0)
    }

    @Test func disconnectedMountConnectedMountAndReconnect() async throws {
        let session = try await LiveSession(view: Counter())
        #expect(await session.html == "<p>0</p>")
        let first = try await session.connect()
        #expect(first.revision == 1)
        #expect(first.baseRevision == nil)
        _ = try await session.handle(.init(name: "increment"))
        var stream = try await session.subscribe().makeAsyncIterator()
        let snapshot = await stream.next()
        #expect(snapshot?.revision == 2)
        #expect(snapshot?.render.dynamics == ["0": "2"])
        await session.close()
        #expect(await stream.next() == nil)
    }

    @Test func asyncEventsAreSerializedAndRetriesDoNotRepeatEffects() async throws {
        let session = try await LiveSession(view: Counter())
        _ = try await session.connect()
        let revisions = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 { group.addTask { try await session.handle(.init(name: "increment")).revision } }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values.sorted()
        }
        #expect(revisions == Array(2...11))
        #expect(await session.html == "<p>11</p>")
        let event = LiveEvent(id: "retry", name: "increment")
        let first = try await session.handle(event)
        #expect(try await session.handle(event) == first)
        #expect(await session.html == "<p>12</p>")
        await #expect(throws: LiveError.reusedEventID) {
            try await session.handle(.init(id: "retry", name: "noop"))
        }
        await #expect(throws: LiveError.invalidEvent) { try await session.handle(.init(name: "fail")) }
        #expect(try await session.handle(.init(name: "noop")).render.dynamics.isEmpty)
    }

    @Test func slowStreamsCloseAndReconnectFromFullSnapshot() async throws {
        let session = try await LiveSession(view: Counter(), streamLimit: 1)
        var slow = try await session.subscribe().makeAsyncIterator()
        _ = try await session.handle(.init(name: "increment"))
        #expect(await session.subscriberCount == 0)
        _ = await slow.next()
        #expect(await slow.next() == nil)
        var recovered = try await session.subscribe().makeAsyncIterator()
        #expect(await recovered.next()?.render.dynamics == ["0": "2"])
        await session.close()
    }

    @Test func ownershipCapacityAndCleanup() async throws {
        let host = LiveHost(Counter(), capacity: 1)
        let mount = try await host.mount(owner: "alice")
        await #expect(throws: LiveError.capacity) { try await host.mount(owner: "bob") }
        await #expect(throws: LiveError.unauthorized) { try await host.subscribe(mount.id, owner: "bob") }
        _ = try await host.subscribe(mount.id, owner: "alice")
        #expect(try await host.send(mount.id, event: .init(name: "increment")).revision == 2)
        try await host.remove(mount.id, owner: "alice")
        #expect(await host.count == 0)
        await #expect(throws: LiveError.notFound) { try await host.subscribe(mount.id, owner: "alice") }
    }
}
