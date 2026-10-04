/// Resolves components and slots with one cursor. Nested components own their
/// slots; siblings and trailing text remain in their enclosing scope.
public struct ComponentResolver {
    public typealias ResolverError = ESWComponentError

    public static func resolve(_ tokens: [Token]) throws -> [RenderNode] {
        var parser = Parser(tokens: tokens)
        var nodes: [RenderNode] = []
        while parser.index < tokens.count {
            nodes.append(try parser.node())
        }
        return nodes
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func node() throws -> RenderNode {
            let token = tokens[index]
            index += 1
            switch token {
            case .componentTag(let name, let attributes, false, let metadata):
                return .component(try component(name: name, attributes: attributes, metadata: metadata))
            case .componentClose(_, let meta):
                throw ResolverError.unmatchedComponentClose(file: meta.file, line: meta.line, column: meta.column)
            case .slotOpen(_, _, _, let meta), .slotClose(_, let meta):
                throw ResolverError.slotOutsideComponent(file: meta.file, line: meta.line, column: meta.column)
            default:
                return .token(token)
            }
        }

        mutating func component(name: String, attributes: [ComponentAttribute], metadata: Metadata) throws -> ComponentNode {
            var slots: [Slot] = []
            var content: [RenderNode] = []
            while index < tokens.count {
                switch tokens[index] {
                case .componentClose(let closeName, let meta):
                    guard closeName == name else {
                        throw ResolverError.unmatchedComponentClose(file: meta.file, line: meta.line, column: meta.column)
                    }
                    index += 1
                    if !slots.isEmpty, content.allSatisfy(Self.isWhitespace) { content = [] }
                    let slotKeys = Set(slots.map { $0.name.replacingHyphens() })
                    for attribute in attributes {
                        if slotKeys.contains(attribute.key.replacingHyphens()) || (attribute.key == "content" && !content.isEmpty) {
                            throw ESWHTMLDiagnostic(metadata: metadata, message: "'\(attribute.key)' is supplied as both an attribute and a content slot")
                        }
                    }
                    if TemplateValidation.binding(in: attributes) != nil, content.isEmpty {
                        throw ESWHTMLDiagnostic(metadata: metadata, message: ":let requires default content; put :let on the named slot to bind its input")
                    }
                    return ComponentNode(name: name, attributes: attributes, namedSlots: slots,
                                         defaultSlot: content, metadata: metadata)
                case .slotOpen(let slotName, let attributes, let selfClosing, let meta):
                    index += 1
                    let nodes = selfClosing ? [] : try slot(name: slotName, metadata: meta)
                    slots.append(Slot(name: slotName, nodes: nodes, attributes: attributes, metadata: meta))
                case .slotClose(_, let meta):
                    throw ResolverError.unmatchedSlotClose(file: meta.file, line: meta.line, column: meta.column)
                default:
                    content.append(try node())
                }
            }
            throw ResolverError.unterminatedComponent(file: metadata.file, line: metadata.line, column: metadata.column)
        }

        private static func isWhitespace(_ node: RenderNode) -> Bool {
            switch node {
            case .token(.text(let text, _)): return text.allSatisfy(\.isWhitespace)
            case .token(.comment): return true
            default: return false
            }
        }

        mutating func slot(name: String, metadata: Metadata) throws -> [RenderNode] {
            var nodes: [RenderNode] = []
            while index < tokens.count {
                switch tokens[index] {
                case .slotClose(let closeName, let meta):
                    guard closeName == name else {
                        throw ResolverError.unmatchedSlotClose(file: meta.file, line: meta.line, column: meta.column)
                    }
                    index += 1
                    return nodes
                case .componentClose:
                    throw ResolverError.unterminatedSlot(file: metadata.file, line: metadata.line, column: metadata.column)
                default:
                    nodes.append(try node())
                }
            }
            throw ResolverError.unterminatedSlot(file: metadata.file, line: metadata.line, column: metadata.column)
        }
    }
}
