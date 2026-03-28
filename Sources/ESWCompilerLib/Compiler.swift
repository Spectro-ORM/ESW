/// Top-level compile function: source string → generated Swift string.
public func compile(
    source: String,
    filename: String,
    sourceFile: String,
    emitSourceLocations: Bool = true
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
