import ESWCompilerLib
import Algorithms

public struct ComponentResolver {
    public enum ResolverError: Error, Equatable {
        case unterminatedComponent(file: String, line: Int, column: Int)
        case unmatchedComponentClose(file: String, line: Int, column: Int)
        case unterminatedSlot(file: String, line: Int, column: Int)
        case unmatchedSlotClose(file: String, line: Int, column: Int)
        case duplicateSlot(name: String, file: String, line: Int)
        case slotOutsideComponent(file: String, line: Int, column: Int)
    }

    public static func resolve(_ tokens: [Token]) throws -> [RenderNode] {
        var nodes: [RenderNode] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
                        switch token {
            case .componentTag(let name, let attributes, let selfClosing, let metadata):
                if selfClosing {
                    nodes.append(.token(token))
                    index += 1
                } else {
                    // Start of a non-self-closing component
                    let (componentNode, nextIndex) = try resolveComponent(tokens, startIndex: index)
                    nodes.append(.component(componentNode))
                    index = nextIndex
                }
            case .slotOpen, .slotClose:
                // These should be handled inside resolveComponent
                // If they appear here, they are outside a component
                if case .slotOpen(_, let meta) = token {
                    throw ResolverError.slotOutsideComponent(file: meta.file, line: meta.line, column: meta.column)
                } else if case .slotClose(_, let meta) = token {
                    throw ResolverError.slotOutsideComponent(file: meta.file, line: meta.line, column: meta.column)
                }
                index += 1
            case .componentClose(let name, let meta):
                // Unmatched component close (no corresponding open)
                throw ResolverError.unmatchedComponentClose(file: meta.file, line: meta.line, column: meta.column)
            default:
                nodes.append(.token(token))
                index += 1
            }
        }
        return nodes
    }

    private static func resolveComponent(_ tokens: [Token], startIndex: Int) throws -> (ComponentNode, Int) {
        guard case let .componentTag(name, attributes, _, metadata) = tokens[startIndex] else {
            fatalError("Expected componentTag at \(startIndex)")
        }

        var innerTokens: [Token] = []
        var depth = 1
        var currentIndex = startIndex + 1
        var foundMatch = false

        while currentIndex < tokens.count {
            let token = tokens[currentIndex]
            switch token {
            case .componentTag(_, _, let selfClosing, _):
                if selfClosing {
                    innerTokens.append(token)
                } else {
                    depth += 1
                    innerTokens.append(token)
                }
            case .componentClose(let closeName, _):
                if closeName == name {
                    depth -= 1
                    if depth == 0 {
                        foundMatch = true
                        currentIndex += 1
                        break
                    }
                } else {
                    // It's a close tag for a nested component
                    depth -= 1
                    if depth == 0 {
                        // Found a close tag that makes depth 0, but name doesn't match.
                        // This means we have an unmatched component close.
                        throw ResolverError.unmatchedComponentClose(file: metadata.file, line: metadata.line, column: metadata.column)
                    }
                }
                innerTokens.append(token)
            case .slotOpen, .slotClose:
                // Slot tags are content within the component, don't affect depth
                innerTokens.append(token)
            default:
                innerTokens.append(token)
            }
            currentIndex += 1
        }

        if !foundMatch {
            throw ResolverError.unterminatedComponent(file: metadata.file, line: metadata.line, column: metadata.column)
        }

        // Now we have innerTokens. Split them into namedSlots and defaultSlot.
        let (namedSlots, defaultSlot) = try splitSlots(innerTokens)

        // Recursively resolve each region
        let resolvedNamedSlots = try namedSlots.map { (name, nodes) in
            Slot(name: name, nodes: try resolve(nodes))
        }
        let resolvedDefaultSlot = try resolve(defaultSlot)

        let componentNode = ComponentNode(
            name: name,
            attributes: attributes,
            namedSlots: resolvedNamedSlots,
            defaultSlot: resolvedDefaultSlot,
            metadata: metadata
        )

        return (componentNode, currentIndex)
    }

    private static func splitSlots(_ tokens: [Token]) throws -> (namedSlots: [(name: String, nodes: [Token])], defaultSlot: [Token]) {
        var namedSlots: [(name: String, nodes: [Token])] = []
        var defaultSlot: [Token] = []

        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case .slotOpen(let name, let meta):
                // Check for duplicate slot
                if namedSlots.contains(where: { $0.name == name }) {
                    throw ResolverError.duplicateSlot(name: name, file: meta.file, line: meta.line)
                }

                // Find matching slotClose
                var slotTokens: [Token] = []
                var slotDepth = 1
                var j = i + 1
                var foundClose = false

                slotSearchLoop: while j < tokens.count {
                    let slotToken = tokens[j]
                    switch slotToken {
                    case .slotOpen:
                        slotDepth += 1
                        slotTokens.append(slotToken)
                    case .slotClose(let closeName, _):
                        if closeName == name {
                            slotDepth -= 1
                            if slotDepth == 0 {
                                foundClose = true
                                j += 1
                                break slotSearchLoop
                            }
                        }
                        // Different slot name - it's content within this slot
                        slotTokens.append(slotToken)
                    default:
                        slotTokens.append(slotToken)
                    }
                    j += 1
                }

                if !foundClose {
                    // If we didn't find a matching close, it might be an unterminated slot
                    // But we need the metadata from the slotOpen
                    throw ResolverError.unterminatedSlot(file: meta.file, line: meta.line, column: meta.column)
                }

                namedSlots.append((name: name, nodes: slotTokens))
                i = j

            case .slotClose(_, let meta):
                // A slotClose without a preceding slotOpen
                throw ResolverError.unmatchedSlotClose(file: meta.file, line: meta.line, column: meta.column)

            default:
                defaultSlot.append(token)
                i += 1
            }
        }

        return (namedSlots, defaultSlot)
    }
}