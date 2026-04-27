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
    let renderNodes = try ComponentResolver.resolve(bodyTokens)
    let generator = CodeGenerator(
        renderNodes: renderNodes,
        parameters: parameters,
        sourceFile: sourceFile,
        filename: filename,
        emitSourceLocations: emitSourceLocations
    )
    return generator.generate()
}

@Suite("Partials")
struct PartialsTests {

    @Test func partialGeneratesBufferFunction() throws {
        let output = try generate(
            "<%!\nvar user: User\n%>\n<div><%= user.name %></div>",
            filename: "_user_card.esw"
        )
        #expect(output.contains("func _renderUserCardBuffer("))
        #expect(output.contains("user: User"))
        #expect(output.contains(") -> String {"))
        #expect(output.contains("return _buf.finalize()"))
        #expect(!output.contains("Connection"))
        #expect(!output.contains("conn.html"))
    }

    @Test func nonPartialGeneratesStringFunction() throws {
        let output = try generate("<h1>Hello</h1>", filename: "hello.esw")
        #expect(output.contains("func renderHello() -> String {"))
        #expect(output.contains("var _buf = ESWBuffer()"))
        #expect(output.contains("return _buf.finalize()"))
    }

    @Test func partialHasNoConnParam() throws {
        let output = try generate(
            "<%!\nvar user: User\n%>\n<p><%= user.name %></p>",
            filename: "_card.esw"
        )
        #expect(output.contains("func _renderCardBuffer("))
        #expect(!output.contains("conn"))
    }

    @Test func partialAndNonPartialDifferByName() throws {
        let partial = try generate(
            "<%!\nvar user: User\nvar showEmail: Bool = false\n%>\nhello",
            filename: "_info.esw"
        )
        let nonPartial = try generate(
            "<%!\nvar user: User\nvar showEmail: Bool = false\n%>\nhello",
            filename: "info.esw"
        )
        // Names differ
        #expect(partial.contains("func _renderInfoBuffer("))
        #expect(nonPartial.contains("func renderInfo("))
        // Params and return type are identical
        #expect(partial.contains("user: User"))
        #expect(partial.contains("showEmail: Bool = false"))
        #expect(nonPartial.contains("user: User"))
        #expect(nonPartial.contains("showEmail: Bool = false"))
        #expect(partial.contains("-> String"))
        #expect(nonPartial.contains("-> String"))
    }

    @Test func partialNoParams() throws {
        let output = try generate("<footer>Copyright</footer>", filename: "_footer.esw")
        #expect(output.contains("func _renderFooterBuffer() -> String {"))
        #expect(output.contains("return _buf.finalize()"))
    }
}
