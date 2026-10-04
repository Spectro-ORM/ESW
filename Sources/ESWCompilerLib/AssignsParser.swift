import SwiftParser
import SwiftSyntax

public struct Parameter: Equatable, Sendable {
    public let name: String
    public let type: String
    public let defaultValue: String?

    public init(name: String, type: String, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }
}

/// Declarations shared by generated functions and inline expansion.
public struct TemplateDeclarations: Equatable, Sendable {
    public let parameters: [Parameter]
    public let imports: [String]
}

public enum AssignsParser {
    public static func parse(tokens: [Token], file: String) throws -> [Parameter] {
        try declarations(tokens: tokens, file: file).parameters
    }

    public static func declarations(tokens: [Token], file: String) throws -> TemplateDeclarations {
        var foundPriorContent = false
        var header: (String, Metadata)?
        for token in tokens {
            switch token {
            case .assigns(let content, let metadata):
                guard !foundPriorContent, header == nil else {
                    throw ESWAssignsError.assignsNotFirst(file: file, line: metadata.line)
                }
                header = (content, metadata)
            case .text(let text, _):
                if !text.allSatisfy(\.isWhitespace) { foundPriorContent = true }
            case .comment:
                break
            default:
                foundPriorContent = true
            }
        }
        guard let (source, metadata) = header else {
            return TemplateDeclarations(parameters: [], imports: [])
        }
        let tree = Parser.parse(source: escapingLegacyParameterNames(source))
        let locations = SourceLocationConverter(fileName: file, tree: tree)
        var parameters: [Parameter] = []
        var imports: [String] = []
        for statement in tree.statements {
            let line = metadata.line + locations.location(for: statement.positionAfterSkippingLeadingTrivia).line - 1
            func invalid(_ text: String) -> ESWAssignsError {
                .invalidDeclaration(file: file, line: line, text: text)
            }
            guard !statement.hasError else {
                throw invalid(statement.trimmedDescription)
            }
            if let declaration = statement.item.as(ImportDeclSyntax.self) {
                guard declaration.attributes.isEmpty, declaration.modifiers.isEmpty else {
                    throw invalid("template imports cannot have attributes or access modifiers")
                }
                let text = declaration.trimmedDescription
                if !imports.contains(text) { imports.append(text) }
                continue
            }
            guard let declaration = statement.item.as(VariableDeclSyntax.self),
                  declaration.attributes.isEmpty, declaration.modifiers.isEmpty else {
                throw invalid("expected a typed var/let parameter or import: " + statement.trimmedDescription)
            }
            for binding in declaration.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let annotation = binding.typeAnnotation,
                      binding.accessorBlock == nil else {
                    throw invalid("parameters need a name and explicit type: " + binding.trimmedDescription)
                }
                let name = String(pattern.identifier.text.filter { $0 != "`" })
                guard name != "_", !parameters.contains(where: { $0.name == name }) else {
                    throw invalid("duplicate or unnamed parameter '\(name)'")
                }
                parameters.append(Parameter(name: name, type: annotation.type.trimmedDescription,
                                            defaultValue: binding.initializer?.value.trimmedDescription))
            }
        }
        return TemplateDeclarations(parameters: parameters, imports: imports)
    }

    /// Earlier ESW front matter allowed keyword parameter names without
    /// backticks. Keep that spelling at the declaration boundary, while leaving
    /// default expressions, nested declarations, strings and comments intact.
    private static func escapingLegacyParameterNames(_ source: String) -> String {
        var result = ""
        var cursor = source.startIndex
        var depth = 0
        while cursor < source.endIndex {
            if let end = SwiftLexicalScanner.opaqueEnd(in: source, at: cursor) {
                result += source[cursor..<end]
                cursor = end
                continue
            }
            let tail = source[cursor...]
            if depth == 0, tail.hasPrefix("var ") || tail.hasPrefix("let ") {
                let start = source.index(cursor, offsetBy: 4)
                var nameStart = start
                while nameStart < source.endIndex, source[nameStart].isWhitespace { nameStart = source.index(after: nameStart) }
                var nameEnd = nameStart
                while nameEnd < source.endIndex, source[nameEnd].isLetter || source[nameEnd].isNumber || source[nameEnd] == "_" {
                    nameEnd = source.index(after: nameEnd)
                }
                let name = String(source[nameStart..<nameEnd])
                var afterName = nameEnd
                while afterName < source.endIndex, source[afterName].isWhitespace { afterName = source.index(after: afterName) }
                if afterName < source.endIndex, source[afterName] == ":", CodeGenerator.escapedParamName(name) != name {
                    result += source[cursor..<nameStart]
                    result += CodeGenerator.escapedParamName(name)
                    cursor = nameEnd
                    continue
                }
            }
            let character = source[cursor]
            if character == "{" || character == "(" || character == "[" { depth += 1 }
            if character == "}" || character == ")" || character == "]" { depth = max(0, depth - 1) }
            result.append(character)
            cursor = source.index(after: cursor)
        }
        return result
    }
}
