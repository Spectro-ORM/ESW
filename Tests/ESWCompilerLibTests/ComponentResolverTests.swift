import Testing
@testable import ESWCompilerLib

/// Helper to tokenize a string with a default filename.
private func tokenize(_ source: String, file: String = "test.esw") throws -> [Token] {
    var tokenizer = Tokenizer(source: source, file: file)
    return try tokenizer.tokenize()
}

@Suite("ComponentResolver")
struct ComponentResolverTests {

    // MARK: - Self-closing components

    @Test func selfClosingPassesThrough() throws {
        let tokens = try tokenize("<.button />")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .token(let t) = nodes[0] else {
            Issue.record("Expected .token")
            return
        }
        guard case .componentTag(let name, _, let selfClosing, _) = t else {
            Issue.record("Expected .componentTag")
            return
        }
        #expect(name == "button")
        #expect(selfClosing)
    }

    @Test func selfClosingWithAttrsPassesThrough() throws {
        let tokens = try tokenize(#"<.button label="Click" disabled />"#)
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .token(let t) = nodes[0] else {
            Issue.record("Expected .token")
            return
        }
        guard case .componentTag(let name, let attrs, let selfClosing, _) = t else {
            Issue.record("Expected .componentTag")
            return
        }
        #expect(name == "button")
        #expect(attrs.count == 2)
        #expect(selfClosing)
    }

    // MARK: - Open components

    @Test func openComponentWithNoContent() throws {
        let tokens = try tokenize("<.card></.card>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "card")
        #expect(node.attributes.isEmpty)
        #expect(node.namedSlots.isEmpty)
        #expect(node.defaultSlot.isEmpty)
    }

    @Test func openComponentWithBareContent() throws {
        let tokens = try tokenize("<.card><p>Hello</p></.card>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "card")
        #expect(node.namedSlots.isEmpty)
        #expect(node.defaultSlot.count == 1)
        guard case .token(.text(let s, _)) = node.defaultSlot[0] else {
            Issue.record("Expected text token")
            return
        }
        #expect(s == "<p>Hello</p>")
    }

    @Test func openComponentWithAttributesAndContent() throws {
        let tokens = try tokenize(#"<.card title="Hi"><p>Hello</p></.card>"#)
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "card")
        #expect(node.attributes.count == 1)
        #expect(node.attributes[0].key == "title")
        #expect(node.defaultSlot.count == 1)
    }

    // MARK: - Named slots

    @Test func singleNamedSlot() throws {
        let tokens = try tokenize("<.card><:header>Hello</:header></.card>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "card")
        #expect(node.namedSlots.count == 1)
        #expect(node.namedSlots[0].name == "header")
        #expect(node.defaultSlot.isEmpty)
    }

    @Test func multipleNamedSlots() throws {
        let tokens = try tokenize("<.layout><:head></:head><:body></:body></.layout>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "layout")
        #expect(node.namedSlots.count == 2)

        // Sort by name since we're using an unordered array
        let sortedSlots = node.namedSlots.sorted { $0.name < $1.name }
        #expect(sortedSlots[0].name == "body")
        #expect(sortedSlots[1].name == "head")
        #expect(node.defaultSlot.isEmpty)
    }

    @Test func namedSlotsWithBareContent() throws {
        let tokens = try tokenize("<.card><:header>Hi</:header><p>Body</p></.card>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.namedSlots.count == 1)
        #expect(node.namedSlots[0].name == "header")
        #expect(node.defaultSlot.count == 1)
    }

    @Test func nestedComponentInsideSlot() throws {
        let tokens = try tokenize(#"<.card><:header><.icon name="star" /></:header></.card>"#)
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.namedSlots.count == 1)
        let headerSlot = node.namedSlots[0]
        #expect(headerSlot.name == "header")
        #expect(headerSlot.nodes.count == 1)
        guard case .token(.componentTag(let iconName, _, _, _)) = headerSlot.nodes[0] else {
            Issue.record("Expected componentTag in slot")
            return
        }
        #expect(iconName == "icon")
    }

    @Test func slotWithHyphenatedName() throws {
        let tokens = try tokenize("<.card><:top-bar>Hi</:top-bar></.card>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.namedSlots.count == 1)
        #expect(node.namedSlots[0].name == "top-bar")
    }

    // MARK: - Nested components

    @Test func nestedComponents() throws {
        let tokens = try tokenize("<.outer><.inner /></.outer>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let node) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(node.name == "outer")
        #expect(node.defaultSlot.count == 1)
        guard case .token(.componentTag(let innerName, _, _, _)) = node.defaultSlot[0] else {
            Issue.record("Expected componentTag in defaultSlot")
            return
        }
        #expect(innerName == "inner")
    }

    @Test func deeplyNestedComponents() throws {
        let tokens = try tokenize("<.a><.b><.c /></.b></.a>")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 1)
        guard case .component(let aNode) = nodes[0] else {
            Issue.record("Expected .component")
            return
        }
        #expect(aNode.name == "a")
        #expect(aNode.defaultSlot.count == 1)
        guard case .component(let bNode) = aNode.defaultSlot[0] else {
            Issue.record("Expected .component for b")
            return
        }
        #expect(bNode.name == "b")
        #expect(bNode.defaultSlot.count == 1)
        guard case .token(.componentTag(let cName, _, _, _)) = bNode.defaultSlot[0] else {
            Issue.record("Expected componentTag for c")
            return
        }
        #expect(cName == "c")
    }

    // MARK: - Error cases

    @Test func unterminatedComponent() throws {
        let tokens = try tokenize("<.card><p>Hi</p>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func unmatchedComponentClose() throws {
        let tokens = try tokenize("</.card>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func unterminatedSlot() throws {
        let tokens = try tokenize("<.card><:header>Hi</.card>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func unmatchedSlotClose() throws {
        let tokens = try tokenize("<.card></:header></.card>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func duplicateSlot() throws {
        let tokens = try tokenize("<.card><:header>A</:header><:header>B</:header></.card>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func slotOutsideComponent() throws {
        let tokens = try tokenize("<:header>Hi</:header>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    @Test func slotCloseOutsideComponent() throws {
        let tokens = try tokenize("</:header>")
        #expect(throws: ComponentResolver.ResolverError.self) {
            let _ = try ComponentResolver.resolve(tokens)
        }
    }

    // MARK: - Mixed content

    @Test func textAndComponentsMixed() throws {
        let tokens = try tokenize("Hello <.button /> world")
        let nodes = try ComponentResolver.resolve(tokens)

        #expect(nodes.count == 3)
        guard case .token(.text(let t1, _)) = nodes[0] else {
            Issue.record("Expected text")
            return
        }
        #expect(t1 == "Hello ")
        guard case .token(.componentTag(_, _, _, _)) = nodes[1] else {
            Issue.record("Expected componentTag")
            return
        }
        guard case .token(.text(let t2, _)) = nodes[2] else {
            Issue.record("Expected text")
            return
        }
        #expect(t2 == " world")
    }
}
