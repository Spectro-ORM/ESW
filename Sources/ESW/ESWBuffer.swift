/// Accumulates HTML for a string-returning compiled template.
///
/// Generated code appends literal markup with ``append(_:)`` and dynamic text
/// with ``appendEscaped(_:)``. Applications normally call a generated renderer.
public struct ESWBuffer: Sendable {
    private var content: String = ""

    /// Creates an empty buffer.
    public init() {}

    /// Appends literal markup without escaping it.
    public mutating func append(_ string: String) {
        content += string
    }

    /// Appends a value using the HTML-body rules of ``ESW/escape(_:)``.
    public mutating func appendEscaped<T>(_ value: T) {
        content += ESW.escape(value)
    }

    /// Appends raw HTML; the caller owns its escaping and trust decision.
    public mutating func appendUnsafe(_ string: String) {
        content += string
    }

    /// Renders a keyed comprehension as ordinary HTML in a string template.
    public mutating func appendKeyed(_ body: (inout ESWBuffer) -> Void) {
        body(&self)
    }

    /// Keys are type-checked but do not alter string-rendered HTML.
    public mutating func append<Key: Encodable>(key: Key, _ body: (inout ESWBuffer) -> Void) {
        body(&self)
    }

    /// Returns the accumulated HTML without clearing the buffer.
    public func finalize() -> String {
        return content
    }
}
