/// Generates Swift source for a template renderer without executing the template.
///
/// Ordinary templates generate a function returning `String`. A `.live.heex`
/// filename selects `ESWLiveRender`; a supplied ``TemplateView`` generates a
/// `render()` extension instead of a free function. The Swift compiler subsequently
/// type-checks expressions, component calls, and member access in the output.
///
/// - Parameters:
///   - source: The complete template text.
///   - filename: Logical template path used for function naming and syntax selection.
///   - sourceFile: Original path used in diagnostics and source-location directives.
///   - emitSourceLocations: Whether to map generated Swift back to the template.
///   - syntax: An explicit syntax, or nil to infer HEEx from the `.heex` suffix.
///   - view: Optional metadata parsed from the associated Swift view file.
/// - Returns: Swift declarations, including their required imports.
/// - Throws: A template syntax, declaration, component, or validation diagnostic.
public func compile(
    source: String,
    filename: String,
    sourceFile: String,
    emitSourceLocations: Bool = true,
    syntax: TemplateSyntax? = nil,
    view: TemplateView? = nil
) throws -> String {
    try generator(source: source, filename: filename, sourceFile: sourceFile,
                  emitSourceLocations: emitSourceLocations, syntax: syntax, view: view).generate()
}

/// Generates an immediately invoked Swift closure expression for macro expansion.
///
/// Expressions capture names from the surrounding Swift scope. Front-matter
/// declarations do not create local variables or apply their defaults.
/// - Parameters:
///   - source: The template text.
///   - sourceFile: A diagnostic label or original file path.
///   - syntax: Text or HTML-aware parsing. The filename does not select it here.
///   - live: Whether the expression returns a structured live render instead of `String`.
/// - Returns: Swift expression source; no imports or standalone function declarations.
/// - Throws: A template diagnostic. Swift type checking happens when the expression compiles.
public func compileExpression(source: String, sourceFile: String = "<inline>", syntax: TemplateSyntax = .esw, live: Bool = false) throws -> String {
    try generator(source: source, filename: sourceFile, sourceFile: sourceFile,
                  emitSourceLocations: false, syntax: syntax).generateExpression(live: live)
}

private func generator(source: String, filename: String, sourceFile: String,
                       emitSourceLocations: Bool, syntax: TemplateSyntax?, view: TemplateView? = nil) throws -> CodeGenerator {
    let syntax = syntax ?? (filename.hasSuffix(".heex") ? .heex : .esw)
    var tokenizer = Tokenizer(source: source, file: sourceFile, syntax: syntax)
    let rawTokens = coalescedText(try tokenizer.tokenize())
    let trimmedTokens = WhitespaceTrimmer.trim(rawTokens)
    let declarations = try AssignsParser.declarations(tokens: trimmedTokens, file: sourceFile)
    if let view, !declarations.parameters.isEmpty {
        throw ESWTemplateError("\(sourceFile):1:1: error: typed template inputs belong in '\(view.sourceFile)'; remove the parameter declarations from the template")
    }
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
        imports: declarations.imports + (view?.imports ?? []),
        view: view
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
