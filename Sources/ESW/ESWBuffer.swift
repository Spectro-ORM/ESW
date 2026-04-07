public struct ESWBuffer: Sendable {
    private var content: String = ""

    public init() {}

    public mutating func append(_ string: String) {
        content += string
    }

    public mutating func appendEscaped<T>(_ value: T) {
        content += ESW.escape(value)
    }

    public mutating func appendUnsafe(_ string: String) {
        content += string
    }

    public func finalize() -> String {
        return content
    }
}