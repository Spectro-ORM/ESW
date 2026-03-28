/// Minimal Connection stub for testing ESW plugin without swift-nexus.
public struct Connection {
    public var body: String = ""

    public init() {}

    public func html(_ content: String) -> Connection {
        var copy = self
        copy.body = content
        return copy
    }

    /// Renders a content block and wraps it in a layout.
    /// Usage:
    /// ```swift
    /// conn.html(title: user.name, layout: renderLayout) {
    ///     _renderUserProfileBuffer(user: user)
    /// }
    /// ```
    public func html(
        title: String,
        layout: (Connection, String, String) -> Connection,
        content: () -> String
    ) -> Connection {
        let body = content()
        return layout(self, title, body)
    }
}
