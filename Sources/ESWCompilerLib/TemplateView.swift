import SwiftParser
import SwiftSyntax

/// A Swift view supplies the rendering scope for its associated template.
/// Stored properties, defaults, generics, and helpers remain ordinary Swift;
/// ESW only needs the type name, visibility, and imports for its extension.
public struct TemplateView: Sendable {
    /// The top-level struct name, preserving Swift identifier escaping.
    public let typeName: String
    /// Imports to reproduce in the generated file, including conditional import blocks.
    public let imports: [String]
    /// `public `, `package `, or an empty string for internal access.
    public let accessModifier: String
    /// The Swift view file's original path for diagnostics.
    public let sourceFile: String

    /// The annotated path relative to the Swift view file, or nil for explicit companion metadata.
    public let templatePath: String?

    /// Find explicitly annotated, unconditional top-level structs. The build
    /// plugin supplies every Swift source so adding/removing an annotation also
    /// invalidates its output. No naming convention or macro filesystem reads.
    public static func discover(source: String, sourceFile: String) throws -> [TemplateView] {
        let tree = Parser.parse(source: source)
        let visitor = TemplateAnnotations(viewMode: .sourceAccurate)
        visitor.walk(tree)
        guard !visitor.annotations.isEmpty else { return [] }
        let converter = SourceLocationConverter(fileName: sourceFile, tree: tree)
        func invalid(_ node: some SyntaxProtocol, _ message: String) -> ESWTemplateError {
            let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
            return ESWTemplateError("\(sourceFile):\(location.line):\(location.column): error: \(message)")
        }
        guard !tree.hasError else { throw invalid(tree, "invalid Swift in template view source") }
        var views: [TemplateView] = []
        var accepted: Set<SyntaxIdentifier> = []
        for statement in tree.statements {
            guard let type = statement.item.as(StructDeclSyntax.self) else { continue }
            let attributes = type.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(TemplateAnnotations.matches)
            guard let attribute = attributes.first else { continue }
            guard attributes.count == 1 else { throw invalid(type, "a view can have only one @ESWTemplate") }
            guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
                  arguments.count == 1, let argument = arguments.first, argument.label == nil,
                  let literal = argument.expression.as(StringLiteralExprSyntax.self),
                  let path = literal.representedLiteralValue,
                  !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
                  !path.contains(where: { $0.isNewline || $0 == "\0" }),
                  [".esw", ".hesw", ".heex"].contains(where: path.hasSuffix) else {
                throw invalid(attribute, "@ESWTemplate requires one literal .esw or .hesw path relative to this Swift file")
            }
            views.append(try TemplateView(type: type, imports: imports(in: tree.statements),
                                          sourceFile: sourceFile, templatePath: path))
            accepted.insert(attribute.id)
        }
        if let unsupported = visitor.annotations.first(where: { !accepted.contains($0.id) }) {
            throw invalid(unsupported, "@ESWTemplate requires an unconditional top-level struct")
        }
        return views
    }

    /// Parses metadata from a source containing exactly one unconditional top-level struct.
    ///
    /// The struct must be accessible from a separate generated extension.
    /// Property types and helpers are checked by Swift, not resolved by this parser.
    /// This initializer does not associate a template path; tooling supplies it separately.
    /// - Throws: ``ESWTemplateError`` for malformed Swift or an unsupported declaration.
    public init(source: String, sourceFile: String) throws {
        let tree = Parser.parse(source: source)
        func invalid(_ message: String) -> ESWTemplateError {
            ESWTemplateError("\(sourceFile):1:1: error: \(message)")
        }
        guard !tree.hasError else {
            throw invalid("invalid Swift in template companion")
        }
        let types = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
        guard types.count == 1, let type = types.first else {
            throw invalid("a template companion must declare exactly one top-level struct")
        }
        try self.init(type: type, imports: Self.imports(in: tree.statements), sourceFile: sourceFile, templatePath: nil)
    }

    private init(type: StructDeclSyntax, imports: [String], sourceFile: String, templatePath: String?) throws {
        let modifiers = Set(type.modifiers.map { $0.name.text })
        guard modifiers.isDisjoint(with: ["private", "fileprivate"]) else {
            throw ESWTemplateError("\(sourceFile):1:1: error: template view '\(type.name.text)' must be accessible from its generated extension; use internal or public access")
        }
        self.typeName = type.name.trimmedDescription
        self.imports = imports
        self.accessModifier = modifiers.contains("public") ? "public " : (modifiers.contains("package") ? "package " : "")
        self.sourceFile = sourceFile
        self.templatePath = templatePath
    }

    private static func imports(in statements: CodeBlockItemListSyntax) -> [String] {
        statements.compactMap { statement in
            if let declaration = statement.item.as(ImportDeclSyntax.self) {
                return declaration.trimmedDescription
            }
            guard let conditional = statement.item.as(IfConfigDeclSyntax.self) else { return nil }
            let clauses = conditional.clauses.map { clause -> (String, [String]) in
                let condition = clause.condition.map { " " + $0.trimmedDescription } ?? ""
                let imports = clause.elements?.as(CodeBlockItemListSyntax.self).map { Self.imports(in: $0) } ?? []
                return (clause.poundKeyword.text + condition, imports)
            }
            guard clauses.contains(where: { !$0.1.isEmpty }) else { return nil }
            return (clauses.flatMap { [$0.0] + $0.1 } + ["#endif"]).joined(separator: "\n")
        }
    }
}

private final class TemplateAnnotations: SyntaxVisitor {
    var annotations: [AttributeSyntax] = []

    static func matches(_ attribute: AttributeSyntax) -> Bool {
        ["ESWTemplate", "ESW.ESWTemplate"].contains(attribute.attributeName.trimmedDescription)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if Self.matches(node) { annotations.append(node) }
        return .skipChildren
    }
}
