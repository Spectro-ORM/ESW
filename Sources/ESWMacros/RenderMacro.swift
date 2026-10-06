import SwiftSyntax
import SwiftSyntaxMacros
import SwiftParser
import ESWCompilerLib
import Foundation

// MARK: - Error

struct ESWMacroError: Error, CustomStringConvertible, Sendable {
    let description: String
    init(_ message: String) { description = message }
}

// MARK: - #render

/// Implements `#render("template.esw")`.
///
/// Reads the `.esw` file at compile time, parses it with `ESWCompilerLib`,
/// and expands to an immediately-invoked closure that returns a `String`:
///
/// ```
/// {
///     var _buf = ""
///     // ... generated template body ...
///     return _buf
/// }()
/// ```
///
/// Template variables are captured from the surrounding scope at the call site.
/// If a required variable is missing or has the wrong type, the expansion fails
/// with a standard Swift compiler error pointing to the `#render(...)` call.
public struct RenderMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // First argument: the template file path (must be a string literal)
        guard let firstArg = node.arguments.first else {
            throw ESWMacroError("#render requires a template file path as its first argument")
        }
        let templatePath = try extractString(from: firstArg.expression, hint: "template path")

        // Catch inline HTML passed to #render — should use #esw instead
        if templatePath.contains("<") || templatePath.contains("\n") {
            throw ESWMacroError(
                "#render expects a file path (e.g. #render(\"template.esw\")), not inline HTML. " +
                "Use #esw(\"...\") for inline templates."
            )
        }

        // Resolve the .esw file relative to the invoking source file
        let sourceFilePath = try sourceFile(of: node, in: context)
        let resolvedPath = try resolveTemplate(templatePath, from: sourceFilePath)

        // Read and expand
        let source: String
        do {
            source = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            throw ESWMacroError("Cannot read template '\(templatePath)': \(error.localizedDescription)")
        }
        return try expand(source: source, file: resolvedPath, syntax: TemplateSyntax(path: resolvedPath))
    }

    // MARK: - Shared expansion (reused by InlineESWMacro)

    static func expand(source: String, file: String, syntax: TemplateSyntax = .esw) throws -> ExprSyntax {
        let expression = try compileExpression(source: source, sourceFile: file, syntax: syntax)
        return "\(raw: expression)"
    }

    // MARK: - Helpers

    static func extractString(from expr: ExprSyntax, hint: String) throws -> String {
        guard let lit = expr.as(StringLiteralExprSyntax.self) else {
            throw ESWMacroError("The \(hint) must be a string literal")
        }
        guard let value = lit.representedLiteralValue else {
            throw ESWMacroError("The \(hint) must be a literal without Swift interpolation")
        }
        return value
    }

    private static func sourceFile(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> String {
        guard
            let loc = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .filePath),
            let lit = loc.file.as(StringLiteralExprSyntax.self)
        else {
            throw ESWMacroError("Cannot determine the source file location for #render")
        }
        guard let path = lit.representedLiteralValue else {
            throw ESWMacroError("Cannot decode the source file location for #render")
        }
        return path
    }

    /// Resolves a template name by walking up from the invoking source file,
    /// checking `Views/<name>` and `<name>` directly at each level (up to 6 hops).
    private static func resolveTemplate(_ name: String, from sourceFilePath: String) throws -> String {
        if name.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: name) else {
                throw ESWMacroError("Template not found at absolute path: \(name)")
            }
            return name
        }

        let fm = FileManager.default
        var dir = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()

        for _ in 0..<6 {
            let inViews = dir.appendingPathComponent("Views").appendingPathComponent(name)
            if fm.fileExists(atPath: inViews.path) { return inViews.path }

            let direct = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: direct.path) { return direct.path }

            let parent = dir.deletingLastPathComponent()
            guard parent != dir else { break }
            dir = parent
        }

        throw ESWMacroError(
            "Template '\(name)' not found. Searched from: \(URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent().path)"
        )
    }
}
