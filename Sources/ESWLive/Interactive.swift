@_exported import ESW
import Foundation

/// An application defines the state, loads it, handles events, and renders it.
/// Authorization of domain operations belongs in `handleEvent`.
public protocol Interactive: Sendable {
    /// The value owned by one live session. Prefer value types for state transitions.
    associatedtype State: Sendable
    /// Loads state for the initial render and again for the first connection.
    /// Inspect ``LiveContext/isConnected`` to distinguish those two calls.
    func mount(_ context: LiveContext) async throws -> State
    /// Validates an event, performs authorized work, and returns the next state.
    /// Throwing preserves the previous state and render, but cannot undo external effects.
    func handleEvent(_ event: LiveEvent, state: State) async throws -> State
    /// Synchronously renders state, usually with the ESW `#live` macro.
    func render(_ state: State) -> ESWLiveRender
}

@available(*, deprecated, renamed: "Interactive")
public typealias LiveView = Interactive

/// Mount inputs supplied by an application's server adapter.
public struct LiveContext: Sendable {
    /// Route or query parameters selected by the adapter; validate them in the view.
    public var parameters: [String: String]
    /// Trusted server-supplied data, never merged with browser event values.
    public var session: [String: String]
    /// False for the initial render, true for the first connected mount.
    public internal(set) var isConnected: Bool

    /// Creates inputs for an initial, disconnected mount.
    public init(parameters: [String: String] = [:], session: [String: String] = [:]) {
        self.parameters = parameters
        self.session = session
        self.isConnected = false
    }
}

/// A named operation with repeated string values and optional revision checking.
///
/// Reuse the complete event when retrying a lost reply. An ID paired with a
/// different name, values, or base revision is rejected while its outcome is retained.
public struct LiveEvent: Codable, Equatable, Sendable {
    /// The request identity retained across retries.
    public let id: String
    /// The operation interpreted by the view's event handler.
    public let name: String
    /// Form or event fields. Repeated names remain arrays; bracketed names stay literal.
    public let values: [String: [String]]
    /// The expected current revision, or nil for an unchecked server-side event.
    public let baseRevision: Int?

    /// Creates an event. Session admission performs payload and revision validation.
    public init(id: String = UUID().uuidString, name: String, values: [String: [String]] = [:], baseRevision: Int? = nil) {
        self.id = id
        self.name = name
        self.values = values
        self.baseRevision = baseRevision
    }

    /// Returns the first value for a field, or nil if it was not supplied.
    public func value(_ key: String) -> String? { values[key]?.first }

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 128, !name.isEmpty, name.utf8.count <= 128,
              values.count <= 128 else { throw LiveError.invalidEvent }
        var size = 0
        for (key, entries) in values {
            guard key.utf8.count <= 256, entries.count <= 128 else { throw LiveError.invalidEvent }
            size += key.utf8.count + entries.reduce(0) { $0 + $1.utf8.count }
            guard size <= 65_536 else { throw LiveError.invalidEvent }
        }
    }
}

/// Runtime rejection reasons, separate from errors thrown by an application handler.
public enum LiveError: String, Error, Sendable {
    /// The event is malformed, exceeds limits, or is unsupported by the view.
    case invalidEvent
    /// A remembered event ID was reused with a different payload.
    case reusedEventID
    /// The event's base revision does not match the current revision.
    case stale
    /// Event handling was requested before the connected mount.
    case notConnected
    /// The host or session is closed, or a pending mount was invalidated.
    case closed
    /// The requested live instance does not exist or has expired.
    case notFound
    /// The supplied owner or application authorization does not allow access.
    case unauthorized
    /// The session's operation queue is full.
    case busy
    /// The host's mounted and pending instance count has reached capacity.
    case capacity
}

/// A revisioned render patch delivered by a session or transport adapter.
public struct LiveUpdate: Codable, Equatable, Sendable {
    /// The state revision after this update.
    public let revision: Int
    /// The required preceding revision; nil denotes a complete snapshot.
    public let baseRevision: Int?
    /// Complete render data or changed dynamic strings.
    public let render: ESWLivePatch
    /// The acknowledged successful event, or nil for snapshots and failed-event updates.
    public let eventID: String?
}

/// The opaque instance ID and initial render returned by a host mount.
public struct LiveMount: Sendable {
    /// An instance identifier. Possession of the ID does not establish ownership.
    public let id: String
    /// The disconnected initial render, suitable for the first HTTP response.
    public let render: ESWLiveRender
}
