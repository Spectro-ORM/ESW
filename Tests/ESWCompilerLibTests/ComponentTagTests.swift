import Testing
@testable import ESWCompilerLib

/// Full pipeline helper.
private func generate(
    _ source: String,
    filename: String = "test.esw",
    sourceFile: String = "Sources/App/Views/test.esw"
) throws -> String {
    var tokenizer = Tokenizer(source: source, file: sourceFile)
    let rawTokens = try tokenizer.tokenize()
    let trimmedTokens = WhitespaceTrimmer.trim(rawTokens)
    let parameters = try AssignsParser.parse(tokens: trimmedTokens, file: sourceFile)
    let bodyTokens = trimmedTokens.filter {
        if case .assigns = $0 { return false }
        return true
    }
    let renderNodes = try ComponentResolver.resolve(bodyTokens)
    return CodeGenerator(
        renderNodes: renderNodes,
        parameters: parameters,
        sourceFile: sourceFile,
        filename: filename,
        emitSourceLocations: false
    ).generate()
}

@Suite("ComponentTag")
struct ComponentTagTests {

    // MARK: - Tokenizer

    @Test func selfClosingNoAttrs() throws {
        var t = Tokenizer(source: "<.button />", file: "t.esw")
        let tokens = try t.tokenize()
        guard case .componentTag(let name, let attrs, let selfClosing, _) = tokens[0] else {
            Issue.record("Expected componentTag"); return
        }
        #expect(name == "button")
        #expect(attrs.isEmpty)
        #expect(selfClosing)
    }

    @Test func selfClosingStringAttr() throws {
        var t = Tokenizer(source: #"<.button label="Click me" />"#, file: "t.esw")
        let tokens = try t.tokenize()
        guard case .componentTag(_, let attrs, let selfClosing, _) = tokens[0] else {
            Issue.record("Expected componentTag"); return
        }
        #expect(selfClosing)
        #expect(attrs.count == 1)
        #expect(attrs[0].key == "label")
        if case .string(let s) = attrs[0].value { #expect(s == "Click me") }
        else { Issue.record("Expected string value") }
    }

    @Test func selfClosingExprAttr() throws {
        var t = Tokenizer(source: "<.user-card user={currentUser} />", file: "t.esw")
        let tokens = try t.tokenize()
        guard case .componentTag(let name, let attrs, _, _) = tokens[0] else {
            Issue.record("Expected componentTag"); return
        }
        #expect(name == "user-card")
        #expect(attrs.count == 1)
        #expect(attrs[0].key == "user")
        if case .expression(let e) = attrs[0].value { #expect(e == "currentUser") }
        else { Issue.record("Expected expression value") }
    }

    @Test func booleanAttr() throws {
        var t = Tokenizer(source: "<.button disabled />", file: "t.esw")
        let tokens = try t.tokenize()
        guard case .componentTag(_, let attrs, _, _) = tokens[0] else {
            Issue.record("Expected componentTag"); return
        }
        #expect(attrs.count == 1)
        #expect(attrs[0].key == "disabled")
        #expect(attrs[0].value == nil)
    }

    @Test func openAndCloseTag() throws {
        var t = Tokenizer(source: "<.card></.card>", file: "t.esw")
        let tokens = try t.tokenize()
        #expect(tokens.count == 2)
        guard case .componentTag(let openName, _, let selfClosing, _) = tokens[0] else {
            Issue.record("Expected componentTag"); return
        }
        guard case .componentClose(let closeName, _) = tokens[1] else {
            Issue.record("Expected componentClose"); return
        }
        #expect(openName == "card")
        #expect(closeName == "card")
        #expect(!selfClosing)
    }

    @Test func mixedWithNormalHTML() throws {
        var t = Tokenizer(source: "<p>Hello</p><.icon name=\"star\" /><p>World</p>", file: "t.esw")
        let tokens = try t.tokenize()
        #expect(tokens.count == 3)
        guard case .text = tokens[0] else { Issue.record("Expected text"); return }
        guard case .componentTag = tokens[1] else { Issue.record("Expected componentTag"); return }
        guard case .text = tokens[2] else { Issue.record("Expected text"); return }
    }

    // MARK: - CodeGenerator

    @Test func selfClosingNoAttrsCodegen() throws {
        let output = try generate("<.button />")
        #expect(output.contains("_buf.appendUnsafe(Button.render())"))
    }

    @Test func selfClosingStringAttrCodegen() throws {
        let output = try generate(#"<.button label="Click me" />"#)
        #expect(output.contains("Button.render(label:"))
        #expect(output.contains("Click me"))
    }

    @Test func selfClosingExprAttrCodegen() throws {
        let output = try generate("<.user-card user={currentUser} />")
        #expect(output.contains("UserCard.render(user: currentUser)"))
    }

    @Test func booleanAttrCodegen() throws {
        let output = try generate("<.button disabled />")
        #expect(output.contains("Button.render(disabled: true)"))
    }

    @Test func kebabToPascalCaseMapping() throws {
        let output = try generate("<.custom-nav-link href=\"/\" />")
        #expect(output.contains("CustomNavLink.render("))
    }

    @Test func hyphenatedAttrKeyToUnderscoreCodegen() throws {
        let output = try generate(#"<.button phx-click="increment" />"#)
        #expect(output.contains("phx_click:"))
    }

    @Test func multipleAttrsCodegen() throws {
        let output = try generate(#"<.card title="Hello" expanded={isOpen} />"#)
        #expect(output.contains("Card.render("))
        #expect(output.contains("title:"))
        #expect(output.contains("expanded: isOpen"))
    }

    // MARK: - Slots

    @Test func namedSlotCodegen() throws {
        let output = try generate("<.card><:header>Hello</:header></.card>")
        #expect(output.contains("Card.render("))
        #expect(output.contains("header:"))
        // Slots should be alphabetically ordered in generated code
        #expect(output.contains("header: {"))
        #expect(output.contains("var _buf = ESWBuffer()"))
        #expect(output.contains("return _buf.finalize()"))
    }

    @Test func emptyDefaultSlotOmitsContent() throws {
        let output = try generate("<.card></.card>")
        #expect(output.contains("Card.render()"))
        #expect(!output.contains("content:"))
    }

    @Test func attributesAndSlots() throws {
        let output = try generate(#"<.card title="Hi"><:header>A</:header></.card>"#)
        #expect(output.contains("Card.render("))
        #expect(output.contains("title:"))
        #expect(output.contains("header:"))
    }

    @Test func nestedComponentInSlot() throws {
        let output = try generate(#"<.card><:header><.icon name="star" /></:header></.card>"#)
        #expect(output.contains("Card.render("))
        #expect(output.contains("header:"))
        #expect(output.contains("Icon.render("))
    }

    @Test func bareContentBecomesContentSlot() throws {
        let output = try generate("<.card><p>Hi</p></.card>")
        #expect(output.contains("Card.render("))
        #expect(output.contains("content:"))
        #expect(output.contains("<p>Hi</p>"))
    }
}
