import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - #esw

/// Implements `#esw("...")`.
///
/// Parses the template string literal at compile time and expands to the same
/// immediately-invoked closure as `#render`, without reading any file.
/// Useful for small, co-located templates that don't warrant a separate `.esw` file.
///
/// Swift string interpolations (`\(...)`) inside the literal are rejected —
/// use ESW output tags (`<%= ... %>`) instead.
public struct InlineESWMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let firstArg = node.arguments.first else {
            throw ESWMacroError("#esw requires a template string as its first argument")
        }

        guard let lit = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            throw ESWMacroError("#esw: the template must be a string literal, not a variable")
        }

        // Reject Swift string interpolations inside the template
        var source = ""
        for segment in lit.segments {
            if let text = segment.as(StringSegmentSyntax.self) {
                source += text.content.text
            } else if segment.as(ExpressionSegmentSyntax.self) != nil {
                throw ESWMacroError(
                    "#esw: Swift string interpolation (\\(...)) is not allowed inside templates. " +
                    "Use ESW output tags (<%= ... %>) instead."
                )
            }
        }

        return try RenderMacro.expand(source: source, file: "<inline>")
    }
}
