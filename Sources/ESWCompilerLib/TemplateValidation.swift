import SwiftParser
import SwiftSyntax

enum TemplateValidation {
    static func binding(in attributes: [ComponentAttribute]) -> String? {
        guard let attribute = attributes.first(where: { $0.key == ":let" }),
              case .expression(let pattern) = attribute.value else { return nil }
        return pattern.trimmingWhitespace()
    }

    static func validateBinding(in attributes: [ComponentAttribute], selfClosing: Bool, metadata: Metadata) throws {
        guard let pattern = binding(in: attributes) else { return }
        guard !selfClosing else {
            throw ESWHTMLDiagnostic(metadata: metadata, message: ":let requires a component or slot with content")
        }
        let tree = Parser.parse(source: "let \(pattern) = __esw_slot_value")
        guard !tree.hasError, tree.statements.count == 1,
              let declaration = tree.statements.first?.item.as(VariableDeclSyntax.self),
              declaration.bindings.count == 1, let binding = declaration.bindings.first,
              binding.typeAnnotation == nil, binding.initializer?.value.trimmedDescription == "__esw_slot_value" else {
            throw ESWHTMLDiagnostic(metadata: metadata, message: ":let requires a Swift binding pattern, such as {row} or {(key, value)}")
        }
    }
}
