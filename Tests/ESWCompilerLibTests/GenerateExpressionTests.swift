import Testing
@testable import ESWCompilerLib

private func generateExpression(
    _ source: String,
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
        filename: "test.esw",
        emitSourceLocations: false
    ).generateExpression()
}

@Suite("GenerateExpression")
struct GenerateExpressionTests {

    @Test func producesIICE() throws {
        let output = try generateExpression("hello")
        #expect(output.hasPrefix("{"))
        #expect(output.hasSuffix("}()"))
    }

    @Test func noFunctionWrapperOrImports() throws {
        let output = try generateExpression("hello")
        #expect(!output.contains("func render"))
        #expect(!output.contains("import ESW"))
    }

    @Test func simpleText() throws {
        let output = try generateExpression("<h1>Hello</h1>")
        #expect(output.contains("_buf.append("))
        #expect(output.contains("<h1>Hello</h1>"))
    }

    @Test func escapedOutput() throws {
        let output = try generateExpression("<%= name %>")
        #expect(output.contains("_buf.appendEscaped(name)"))
    }

    @Test func rawOutput() throws {
        let output = try generateExpression("<%== html %>")
        #expect(output.contains("_buf.appendUnsafe(html)"))
    }

    @Test func codeBlock() throws {
        let output = try generateExpression("<% let x = 1 %>")
        #expect(output.contains("let x = 1"))
    }

    @Test func selfClosingComponent() throws {
        let output = try generateExpression(#"<.button label="Click" />"#)
        #expect(output.contains("Button.render(label:"))
    }

    @Test func namedSlotWithOutputTag() throws {
        let output = try generateExpression("<.card><:header><%= title %></:header></.card>")
        #expect(output.contains("header: {"))
        #expect(output.contains("_buf.appendEscaped(title)"))
        #expect(!output.contains("header: {,"))
    }

    @Test func defaultSlotWithOutputTag() throws {
        let output = try generateExpression("<.card><%= body %></.card>")
        #expect(output.contains("content: {"))
        #expect(output.contains("_buf.appendEscaped(body)"))
        #expect(!output.contains("content: {,"))
    }

    @Test func namedSlotWithCodeBlock() throws {
        let output = try generateExpression("<.card><:header><% let x = 1 %></:header></.card>")
        #expect(output.contains("header: {"))
        #expect(output.contains("let x = 1"))
        #expect(!output.contains("header: {,"))
    }
}
