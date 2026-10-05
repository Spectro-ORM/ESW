import Foundation

/// Owns live instances for one route. IDs are opaque and bound to a trusted
/// owner supplied by the HTTP adapter. Instances expire after a fixed lifetime.
public actor LiveHost<View: LiveView> {
    private struct Entry: Sendable {
        let owner: String
        let session: LiveSession<View>
        let expiry: Task<Void, Never>
    }
    private struct PendingMount {
        let owner: String
        var valid = true
    }
    private let view: View
    private let capacity: Int
    private let lifetime: Duration
    private var entries: [String: Entry] = [:]
    private var pendingMounts: [UUID: PendingMount] = [:]
    private var closed = false

    /// Creates a registry for one view type.
    /// - Parameters:
    ///   - view: A reusable view definition; each mount gets separate state.
    ///   - capacity: Maximum live instances, including pending mounts. Must be positive.
    ///   - lifetime: Fixed lifetime after mount, not extended by activity. Must be positive.
    public init(_ view: View, capacity: Int = 1_000, lifetime: Duration = .seconds(3_600)) {
        precondition(capacity > 0 && lifetime > .zero)
        self.view = view
        self.capacity = capacity
        self.lifetime = lifetime
    }

    deinit { for entry in entries.values { entry.expiry.cancel() } }

    /// The number of registered instances, excluding mounts still in progress.
    public var count: Int { entries.count }

    /// Creates an instance bound to a nonempty, trusted owner token.
    /// - Returns: An opaque identifier and the disconnected initial render.
    /// - Throws: A mount error, or ``LiveError`` when closed, unauthorized, or full.
    public func mount(owner: String, context: LiveContext = .init()) async throws -> LiveMount {
        guard !closed else { throw LiveError.closed }
        guard !owner.isEmpty else { throw LiveError.unauthorized }
        guard entries.count + pendingMounts.count < capacity else { throw LiveError.capacity }
        let reservation = UUID()
        pendingMounts[reservation] = PendingMount(owner: owner)
        defer { pendingMounts.removeValue(forKey: reservation) }
        let session = try await LiveSession(view: view, context: context)
        let render = await session.snapshot
        guard !Task.isCancelled, pendingMounts[reservation]?.valid == true, !closed else {
            await session.close()
            try Task.checkCancellation()
            throw LiveError.closed
        }
        let id = UUID().uuidString
        let lifetime = lifetime
        let expiry = Task { [weak self] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            await self?.expire(id)
        }
        entries[id] = Entry(owner: owner, session: session, expiry: expiry)
        return LiveMount(id: id, render: render)
    }

    /// Checks ownership and opens a stream beginning with a complete snapshot.
    /// The first subscription also performs the connected mount.
    public func subscribe(_ id: String, owner: String) async throws -> AsyncStream<LiveUpdate> {
        try await session(id, owner: owner).subscribe()
    }

    /// Checks ownership and dispatches an event through the instance's session queue.
    /// HTTP adapters must separately validate CSRF, origin, and application access.
    public func handle(_ id: String, owner: String, event: LiveEvent) async throws -> LiveUpdate {
        try await session(id, owner: owner).handle(event)
    }

    /// Server-originated events use the same serialized handler and diff path.
    /// This bypasses owner validation. Expose it only to trusted server code;
    /// the instance must already be connected.
    public func send(_ id: String, event: LiveEvent) async throws -> LiveUpdate {
        guard let entry = entries[id] else { throw LiveError.notFound }
        return try await entry.session.handle(event)
    }

    /// Checks ownership, then removes one instance and closes its session.
    public func remove(_ id: String, owner: String) async throws {
        _ = try session(id, owner: owner)
        await expire(id)
    }

    /// Permanently closes the host and all registered sessions.
    /// Suspended mounts cannot register after shutdown.
    public func shutdown() async {
        closed = true
        let current = entries
        entries.removeAll()
        for entry in current.values {
            entry.expiry.cancel()
            await entry.session.close()
        }
    }

    /// Call on logout or permission revocation to close already-open streams.
    public func invalidate(owner: String) async {
        // Keep reservations counted until suspended mounts return, but prevent
        // those mounts from registering after the owner's access was revoked.
        for id in pendingMounts.keys where pendingMounts[id]?.owner == owner {
            pendingMounts[id]?.valid = false
        }
        let ids = entries.compactMap { $0.value.owner == owner ? $0.key : nil }
        let revoked = ids.compactMap { entries.removeValue(forKey: $0) }
        for entry in revoked {
            entry.expiry.cancel()
            await entry.session.close()
        }
    }

    private func session(_ id: String, owner: String) throws -> LiveSession<View> {
        guard let entry = entries[id] else { throw LiveError.notFound }
        guard entry.owner == owner else { throw LiveError.unauthorized }
        return entry.session
    }

    private func expire(_ id: String) async {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.expiry.cancel()
        await entry.session.close()
    }
}
