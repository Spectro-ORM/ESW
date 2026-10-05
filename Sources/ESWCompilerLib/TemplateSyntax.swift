/// Selects text-template scanning or HTML-aware validation and interpolation.
public enum TemplateSyntax: Sendable {
    /// EEx-style text templates with Swift code and component tags.
    case esw
    /// HTML-aware templates: validated tags, brace expressions and attributes.
    case heex
}

/// A located HTML-structure, expression, or directive diagnostic.
public struct ESWHTMLDiagnostic: Error, Equatable, Sendable, CustomStringConvertible {
    /// The original template location.
    public let metadata: Metadata
    /// The explanation without the formatted location prefix.
    public let message: String

    /// A compiler-style `file:line:column: error: message` diagnostic.
    public var description: String {
        "\(metadata.file):\(metadata.line):\(metadata.column): error: \(message)"
    }
}
