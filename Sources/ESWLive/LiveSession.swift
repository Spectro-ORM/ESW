import ESW
import Foundation

/// One server-owned view. An explicit queue covers the entire async mutation,
/// because actor isolation alone permits other events to run during `await`.
public actor LiveSession<View: Interactive> {
    private let view: View
    private let context: LiveContext
    private var state: View.State
    private var rendered: ESWLiveRender
    private var revision = 0
    private var connected = false
    private var closed = false
    private var tail: Task<LiveUpdate, any Error>?
    private var tailID: UUID?
    private var jobs: [UUID: Task<LiveUpdate, any Error>] = [:]
    private var replies: [(LiveEvent, Result<LiveUpdate, any Error>)] = []
    private var subscribers: [UUID: AsyncStream<LiveUpdate>.Continuation] = [:]
    private let queueLimit: Int
    private let streamLimit: Int

    /// Mounts and renders a disconnected instance.
    /// - Parameters:
    ///   - view: The application's state, event, and rendering implementation.
    ///   - context: Server-supplied mount inputs.
    ///   - queueLimit: Maximum accepted operations, including the running one; must be positive.
    ///   - streamLimit: Maximum buffered updates for a subscriber; must be positive.
    /// - Throws: An error from the view's initial mount.
    public init(view: View, context: LiveContext = .init(), queueLimit: Int = 32, streamLimit: Int = 16) async throws {
        precondition(queueLimit > 0 && streamLimit > 0)
        self.view = view
        self.context = context
        self.queueLimit = queueLimit
        self.streamLimit = streamLimit
        let initial = try await view.mount(context)
        self.state = initial
        self.rendered = view.render(initial)
    }

    /// The complete HTML of the latest committed state.
    public var html: String { rendered.html }
    /// The structured render of the latest committed state.
    public var snapshot: ESWLiveRender { rendered }
    /// The number of open subscribers. A new subscription replaces the previous one.
    public var subscriberCount: Int { subscribers.count }

    /// Mounts connected state once and returns a complete snapshot.
    /// Further calls reuse the connected state without remounting it.
    public func connect() async throws -> LiveUpdate { try await enqueue(.connect) }

    /// Queues an event, then commits and publishes its resulting render.
    ///
    /// Call ``connect()`` or ``subscribe()`` before sending events. Up to 128 admitted
    /// outcomes, including handler failures, are remembered for identical retries.
    /// A supplied base revision must match unless a cached outcome is returned.
    /// Handler failures retain state but consume a revision and publish an empty patch.
    /// Cancellation of the calling task does not cancel an accepted mutation.
    ///
    /// - Throws: Payload, lifecycle, capacity, or revision errors, or the handler's error.
    public func handle(_ event: LiveEvent) async throws -> LiveUpdate {
        try event.validate()
        return try await enqueue(.event(event))
    }

    /// Reconnection always starts with a full snapshot. Slow consumers are
    /// disconnected when their bounded queue fills, then reconnect to resync.
    public func subscribe() async throws -> AsyncStream<LiveUpdate> {
        _ = try await connect()
        guard !closed else { throw LiveError.closed }
        // A live instance belongs to one page; replace any obsolete connection.
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
        let id = UUID()
        let (stream, continuation) = AsyncStream<LiveUpdate>.makeStream(bufferingPolicy: .bufferingOldest(streamLimit))
        subscribers[id] = continuation
        continuation.yield(currentUpdate())
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }

    /// Permanently closes the session, finishes streams, and cancels queued work.
    /// Cancellation is cooperative and cannot roll back external side effects.
    public func close() {
        closed = true
        for job in jobs.values { job.cancel() }
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
        replies.removeAll()
    }

    private enum Operation: Sendable { case connect, event(LiveEvent) }

    private func enqueue(_ operation: Operation) async throws -> LiveUpdate {
        guard !closed else { throw LiveError.closed }
        guard jobs.count < queueLimit else { throw LiveError.busy }
        let previous = tail
        let id = UUID()
        let job = Task { [self] in
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            return try await perform(operation)
        }
        jobs[id] = job
        tail = job
        tailID = id
        defer {
            jobs.removeValue(forKey: id)
            if tailID == id { tail = nil; tailID = nil }
        }
        // Request cancellation does not cancel an accepted mutation. A retry
        // retains the event ID and receives the original acknowledgement.
        return try await job.value
    }

    private func perform(_ operation: Operation) async throws -> LiveUpdate {
        guard !closed else { throw LiveError.closed }
        switch operation {
        case .connect:
            if !connected {
                var context = context
                context.isConnected = true
                let initial = try await view.mount(context)
                try Task.checkCancellation()
                guard !closed else { throw LiveError.closed }
                state = initial
                rendered = view.render(initial)
                revision += 1
                connected = true
            }
            return currentUpdate()
        case .event(let event):
            guard connected else { throw LiveError.notConnected }
            if let (original, reply) = replies.first(where: { $0.0.id == event.id }) {
                guard original == event else { throw LiveError.reusedEventID }
                return try reply.get()
            }
            // After the bounded acknowledgement cache evicts an old request,
            // its old revision prevents a delayed retry from executing again.
            if let base = event.baseRevision, base != revision { throw LiveError.stale }
            let next: View.State
            do {
                next = try await view.handleEvent(event, state: state)
            } catch {
                try Task.checkCancellation()
                guard !closed else { throw LiveError.closed }
                // An admitted failure also consumes its revision. Otherwise a
                // lost error reply could rerun effects after cache eviction.
                let update = LiveUpdate(revision: revision + 1, baseRevision: revision,
                                        render: rendered.diff(to: rendered), eventID: nil)
                revision += 1
                remember(event, result: .failure(error))
                publish(update)
                throw error
            }
            try Task.checkCancellation()
            guard !closed else { throw LiveError.closed }
            let nextRender = view.render(next)
            let update = LiveUpdate(revision: revision + 1, baseRevision: revision,
                                    render: rendered.diff(to: nextRender), eventID: event.id)
            state = next
            rendered = nextRender
            revision += 1
            remember(event, result: .success(update))
            publish(update)
            return update
        }
    }

    private func remember(_ event: LiveEvent, result: Result<LiveUpdate, any Error>) {
        replies.append((event, result))
        if replies.count > 128 { replies.removeFirst() }
    }

    private func currentUpdate() -> LiveUpdate {
        LiveUpdate(revision: revision, baseRevision: nil, render: rendered.snapshot, eventID: nil)
    }

    private func publish(_ update: LiveUpdate) {
        var ended: [UUID] = []
        for (id, continuation) in subscribers {
            switch continuation.yield(update) {
            case .enqueued: break
            case .dropped, .terminated: continuation.finish(); ended.append(id)
            @unknown default: continuation.finish(); ended.append(id)
            }
        }
        for id in ended { subscribers.removeValue(forKey: id) }
    }

    private func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }
}
