public enum TemplateSyntax: Sendable {
    /// EEx-style text templates with Swift code and component tags.
    case esw
    /// HTML-aware templates: validated tags, brace expressions and attributes.
    case heex
}

public struct ESWHTMLDiagnostic: Error, Equatable, Sendable, CustomStringConvertible {
    public let metadata: Metadata
    public let message: String

    public var description: String {
        "\(metadata.file):\(metadata.line):\(metadata.column): error: \(message)"
    }
}
