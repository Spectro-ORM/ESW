import SwiftSyntax
import SwiftSyntaxMacros
import SwiftParser
import ESWCompilerLib

// MARK: - #esw, #hesw and #live

/// Implements `#esw("...")`, `#hesw("...")` and `#live("...")`.
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
        let macroName = "#" + node.macroName.text
        let live = node.macroName.text == "live"
        let syntax: TemplateSyntax = ["hesw", "heex", "live"].contains(node.macroName.text) ? .hesw : .esw
        guard let firstArg = node.arguments.first else {
            throw ESWMacroError("\(macroName) requires a template string as its first argument")
        }

        guard let lit = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            throw ESWMacroError("\(macroName): the template must be a string literal, not a variable")
        }

        // Reject Swift string interpolations inside the template
        for segment in lit.segments {
            if segment.as(ExpressionSegmentSyntax.self) != nil {
                throw ESWMacroError(
                    "\(macroName): Swift string interpolation (\\(...)) is not allowed inside templates. " +
                    (syntax == .hesw ? "Use {expression} instead." : "Use ESW output tags (<%= ... %>) instead.")
                )
            }
        }
        guard let source = lit.representedLiteralValue else {
            throw ESWMacroError("Invalid template string literal")
        }
        let expression = try compileExpression(source: source, syntax: syntax, live: live)
        return "\(raw: expression)"
    }
}
