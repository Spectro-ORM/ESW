/// Selects text-template scanning or HTML-aware validation and interpolation.
public enum TemplateSyntax: Sendable {
    /// EEx-style text templates with Swift code and component tags.
    case esw
    /// HESW, HTML-aware ESW: validated tags, brace expressions and attributes.
    case hesw

    @available(*, deprecated, renamed: "hesw")
    public static var heex: TemplateSyntax { .hesw }

    /// Infers syntax from a template path: `.hesw` (or deprecated `.heex`) selects HESW.
    public init(path: String) {
        self = path.hasSuffix(".hesw") || path.hasSuffix(".heex") ? .hesw : .esw
    }

    /// Reports whether a path names a `.live.hesw` (or deprecated `.live.heex`) template.
    public static func isLive(path: String) -> Bool {
        path.hasSuffix(".live.hesw") || path.hasSuffix(".live.heex")
    }
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
