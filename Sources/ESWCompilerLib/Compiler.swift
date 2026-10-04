/// Top-level compile function: source string → generated Swift string.
public func compile(
    source: String,
    filename: String,
    sourceFile: String,
    emitSourceLocations: Bool = true,
    syntax: TemplateSyntax? = nil
) throws -> String {
    try generator(source: source, filename: filename, sourceFile: sourceFile,
                  emitSourceLocations: emitSourceLocations, syntax: syntax).generate()
}

/// The same compiler pipeline used by file and inline macros.
public func compileExpression(source: String, sourceFile: String = "<inline>", syntax: TemplateSyntax = .esw) throws -> String {
    try generator(source: source, filename: sourceFile, sourceFile: sourceFile,
                  emitSourceLocations: false, syntax: syntax).generateExpression()
}

private func generator(source: String, filename: String, sourceFile: String,
                       emitSourceLocations: Bool, syntax: TemplateSyntax?) throws -> CodeGenerator {
    let syntax = syntax ?? (filename.hasSuffix(".heex") ? .heex : .esw)
    var tokenizer = Tokenizer(source: source, file: sourceFile, syntax: syntax)
    let rawTokens = coalescedText(try tokenizer.tokenize())
    let trimmedTokens = WhitespaceTrimmer.trim(rawTokens)
    let declarations = try AssignsParser.declarations(tokens: trimmedTokens, file: sourceFile)
    let bodyTokens = trimmedTokens.filter {
        if case .assigns = $0 { return false }
        return true
    }

    let renderNodes = try ComponentResolver.resolve(bodyTokens)

    let generator = CodeGenerator(
        renderNodes: renderNodes,
        parameters: declarations.parameters,
        sourceFile: sourceFile,
        filename: filename,
        emitSourceLocations: emitSourceLocations,
        imports: declarations.imports
    )
    return generator
}

/// HTML lexing splits tags into pieces for validation. Emit adjacent literal
/// pieces together, retaining the first source location and expression order.
private func coalescedText(_ tokens: [Token]) -> [Token] {
    var result: [Token] = []
    var text = ""
    var location: Metadata?
    func flush() {
        if let metadata = location { result.append(.text(text, metadata: metadata)) }
        text = ""
        location = nil
    }
    for token in tokens {
        if case .text(let value, let metadata) = token {
            if location == nil { location = metadata }
            text.append(contentsOf: value)
        } else {
            flush()
            result.append(token)
        }
    }
    flush()
    return result
}
