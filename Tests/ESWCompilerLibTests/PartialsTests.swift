import Testing
@testable import ESWCompilerLib

/// Full pipeline helper.
private func generate(
    _ source: String,
    filename: String,
    sourceFile: String = "Sources/App/Views/test.esw",
    emitSourceLocations: Bool = false
) throws -> String {
    var tokenizer = Tokenizer(source: source, file: sourceFile)
    let rawTokens = try tokenizer.tokenize()
    let trimmedTokens = WhitespaceTrimmer.trim(rawTokens)
    let parameters = try AssignsParser.parse(tokens: trimmedTokens, file: sourceFile)
    let bodyTokens = trimmedTokens.filter {
        if case .assigns = $0 { return false }
        return true
    }
    let generator = CodeGenerator(
        tokens: bodyTokens,
        parameters: parameters,
        sourceFile: sourceFile,
        filename: filename,
        emitSourceLocations: emitSourceLocations
    )
    return generator.generate()
}

@Suite("Partials")
struct PartialsTests {

    @Test func partialGeneratesBothFunctions() throws {
        let output = try generate(
            "<%!\nvar user: User\n%>\n<div><%= user.name %></div>",
            filename: "_user_card.esw"
        )
        // Buffer variant
        #expect(output.contains("func _renderUserCardBuffer("))
        #expect(output.contains(") -> String {"))
        #expect(output.contains("return _buf"))
        // Connection variant
        #expect(output.contains("func renderUserCard("))
        #expect(output.contains("conn: Connection"))
        #expect(output.contains(") -> Connection {"))
        #expect(output.contains("conn.html(_renderUserCardBuffer("))
    }

    @Test func nonPartialGeneratesOnlyConnFunction() throws {
        let output = try generate("<h1>Hello</h1>", filename: "hello.esw")
        #expect(output.contains("func renderHello("))
        #expect(!output.contains("Buffer"))
        #expect(output.contains("return conn.html(_buf)"))
    }

    @Test func bufferVariantHasNoConn() throws {
        let output = try generate(
            "<%!\nvar user: User\n%>\n<p><%= user.name %></p>",
            filename: "_card.esw"
        )
        // The buffer function should NOT have conn param
        let bufferLine = output.split(separator: "\n").first { $0.contains("func _renderCardBuffer(") }
        #expect(bufferLine != nil)
        #expect(bufferLine?.contains("conn") == false)
    }

    @Test func connVariantCallsBufferWithArgs() throws {
        let output = try generate(
            "<%!\nvar user: User\nvar showEmail: Bool = false\n%>\nhello",
            filename: "_info.esw"
        )
        #expect(output.contains("_renderInfoBuffer(user: user, showEmail: showEmail)"))
    }

    @Test func partialNoParams() throws {
        let output = try generate("<footer>Copyright</footer>", filename: "_footer.esw")
        #expect(output.contains("func _renderFooterBuffer() -> String {"))
        #expect(output.contains("func renderFooter("))
        #expect(output.contains("conn.html(_renderFooterBuffer())"))
    }
}
