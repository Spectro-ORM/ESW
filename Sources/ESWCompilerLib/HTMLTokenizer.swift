struct HTMLElement {
    let name: String
    let metadata: Metadata
    let directives: Int
    let keyed: Bool
    let interpolateCurly: Bool
}

extension Tokenizer {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr",
    ]

    func htmlDiagnostic(_ message: String, at metadata: Metadata? = nil) -> ESWHTMLDiagnostic {
        ESWHTMLDiagnostic(metadata: metadata ?? Metadata(file: file, line: line, column: column), message: message)
    }

    mutating func openHTMLElement(_ name: String, line: Int, column: Int, directives: Int = 0, keyed: Bool = false, interpolateCurly: Bool = true) {
        let inherited = htmlElements.last?.interpolateCurly ?? true
        htmlElements.append(HTMLElement(name: name, metadata: Metadata(file: file, line: line, column: column),
                                        directives: directives, keyed: keyed, interpolateCurly: inherited && interpolateCurly))
    }

    @discardableResult
    mutating func closeHTMLElement(_ name: String, at metadata: Metadata? = nil) throws -> HTMLElement {
        guard let open = htmlElements.last else {
            throw htmlDiagnostic("unexpected closing tag </\(name)>", at: metadata)
        }
        guard open.name == name else {
            throw htmlDiagnostic("expected </\(open.name)> for tag opened at line \(open.metadata.line), got </\(name)>", at: metadata)
        }
        htmlElements.removeLast()
        return open
    }

    /// HTML mode shares Swift tokenization and component resolution with ESW.
    /// Static HTML remains text; only dynamic attributes add runtime operations.
    mutating func readHTMLToken() throws -> [Token]? {
        let metadata = Metadata(file: file, line: line, column: column)
        if let opening = htmlCommentMetadata {
            if isEExBoundary { return nil }
            var text = ""
            while index < source.endIndex {
                if isEExBoundary { return [.text(text, metadata: metadata)] }
                if source[index...].hasPrefix("-->") {
                    for _ in 0..<3 { text.append(advance()) }
                    htmlCommentMetadata = nil
                    return [.text(text, metadata: metadata)]
                }
                text.append(advance())
            }
            throw htmlDiagnostic("unterminated HTML comment", at: opening)
        }
        if let element = htmlElements.last, element.name == "script" || element.name == "style" {
            if isEExBoundary { return nil }
            if !isRawTextClose(element.name) {
                var text = ""
                while index < source.endIndex, !isRawTextClose(element.name), !isEExBoundary {
                    text.append(advance())
                }
                return [.text(text, metadata: metadata)]
            }
        }
        if source[index...].hasPrefix("<!--") {
            htmlCommentMetadata = metadata
            for _ in 0..<4 { advance() }
            return [.text("<!--", metadata: metadata)]
        }
        if source[index...].prefix(9).lowercased() == "<!doctype" {
            var text = ""
            while let c = peek() {
                text.append(advance())
                if c == ">" { return [.text(text, metadata: metadata)] }
            }
            throw htmlDiagnostic("unterminated doctype", at: metadata)
        }
        let interpolateCurly = htmlElements.last?.interpolateCurly ?? true
        if interpolateCurly, peek() == "\\", peek(offset: 1) == "{" || peek(offset: 1) == "}" {
            advance()
            return [.text(String(advance()), metadata: metadata)]
        }
        if interpolateCurly, peek() == "{" {
            advance()
            let expression = try readExpressionAttributeValue(tagLine: line, tagColumn: column)
            return [.output(expression.trimmingWhitespace(), metadata: metadata)]
        }
        guard peek() == "<" else { return nil }
        if isQualifiedComponentTag(closing: peek(offset: 1) == "/") { return nil }
        if peek(offset: 1) == "/", let next = peek(offset: 2), next.isLetter {
            advance()
            advance()
            let sourceName = readHTMLName()
            let name = sourceName.lowercased()
            skipWhitespace()
            guard peek() == ">" else { throw htmlDiagnostic("malformed closing tag", at: metadata) }
            advance()
            let element = try closeHTMLElement(name, at: metadata)
            return [.text("</\(sourceName)>", metadata: metadata)] + closingDirectives(element.directives, keyed: element.keyed, metadata: metadata)
        }
        guard let next = peek(offset: 1), next.isLetter else { return nil }
        return try readHTMLOpen(metadata: metadata)
    }

    private var isEExBoundary: Bool {
        source[index...].hasPrefix("<%") || source[index...].hasPrefix("%%>")
    }

    private func isRawTextClose(_ name: String) -> Bool {
        let prefix = "</" + name
        guard source[index...].prefix(prefix.count).lowercased() == prefix,
              let after = source.index(index, offsetBy: prefix.count, limitedBy: source.endIndex) else { return false }
        return after == source.endIndex || source[after] == ">" || source[after].isWhitespace
    }

    private mutating func readHTMLName() -> String {
        var name = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":" || c == "." {
            name.append(advance())
        }
        return name
    }

    private mutating func readHTMLOpen(metadata: Metadata) throws -> [Token] {
        advance() // <
        let sourceName = readHTMLName()
        let name = sourceName.lowercased()
        var tokens: [Token] = [.text("<\(sourceName)", metadata: metadata)]
        var keys = Set<String>()
        var condition: String?
        var loop: String?
        var identity: String?
        var interpolateCurly = name != "script" && name != "style"
        var scoped = false
        while index < source.endIndex {
            let separated = peek()?.isWhitespace == true
            skipWhitespace()
            if peek() == ">" || (peek() == "/" && peek(offset: 1) == ">") { break }
            guard separated else { throw htmlDiagnostic("expected whitespace between attributes") }
            let attrMetadata = Metadata(file: file, line: line, column: column)
            if peek() == "{" {
                advance()
                let expression = try readExpressionAttributeValue(tagLine: line, tagColumn: column)
                tokens.append(.htmlAttributes(expression: expression, metadata: attrMetadata))
                continue
            }
            let key = readHTMLName()
            guard let first = key.first, first.isLetter || first == "_" || first == ":" else {
                throw htmlDiagnostic("expected an attribute name or {attributes}")
            }
            guard keys.insert(key.lowercased()).inserted else {
                throw htmlDiagnostic("duplicate attribute '\(key)'", at: attrMetadata)
            }
            let afterKey = index
            let afterKeyLine = line
            let afterKeyColumn = column
            skipWhitespace()
            if key.lowercased() == "phx-no-curly-interpolation" {
                guard peek() != "=" else {
                    throw htmlDiagnostic("phx-no-curly-interpolation is a bare compile-time attribute", at: attrMetadata)
                }
                interpolateCurly = false
                index = afterKey
                line = afterKeyLine
                column = afterKeyColumn
                continue
            }
            if key == ":scoped" {
                guard name == "style" else { throw htmlDiagnostic(":scoped applies only to <style>", at: attrMetadata) }
                guard peek() != "=" else { throw htmlDiagnostic(":scoped is a bare compile-time attribute", at: attrMetadata) }
                scoped = true
                index = afterKey
                line = afterKeyLine
                column = afterKeyColumn
                continue
            }
            guard peek() == "=" else {
                if key.hasPrefix(":") { throw htmlDiagnostic("\(key) requires a Swift expression", at: attrMetadata) }
                tokens.append(.text(" \(key)", metadata: attrMetadata))
                // Leave the separator for the next attribute to consume.
                index = afterKey
                line = afterKeyLine
                column = afterKeyColumn
                continue
            }
            advance()
            skipWhitespace()
            if peek() == "{" {
                advance()
                let expression = try readExpressionAttributeValue(tagLine: attrMetadata.line, tagColumn: attrMetadata.column)
                switch key {
                case ":if": condition = expression
                case ":for": loop = expression
                case ":key": identity = expression
                default:
                    guard !key.hasPrefix(":") else { throw htmlDiagnostic("unsupported directive '\(key)'", at: attrMetadata) }
                    tokens.append(.htmlAttribute(name: key, expression: expression, metadata: attrMetadata))
                }
            } else if let quote = peek(), quote == "\"" || quote == "'" {
                guard !key.hasPrefix(":") else { throw htmlDiagnostic("\(key) requires {expression}", at: attrMetadata) }
                advance()
                var value = ""
                while let c = peek(), c != quote {
                    if source[index...].hasPrefix("<%") {
                        throw htmlDiagnostic("use \(key)={expression} for dynamic attributes", at: attrMetadata)
                    }
                    value.append(advance())
                }
                guard peek() == quote else { throw htmlDiagnostic("unterminated attribute '\(key)'", at: attrMetadata) }
                advance()
                tokens.append(.text(" \(key)=\(quote)\(value)\(quote)", metadata: attrMetadata))
            } else {
                throw htmlDiagnostic("attribute '\(key)' must use quotes or {expression}", at: attrMetadata)
            }
        }
        let selfClosing = peek() == "/"
        if selfClosing { advance() }
        guard peek() == ">" else { throw htmlDiagnostic("unterminated tag <\(name)>", at: metadata) }
        advance()
        if scoped { return try readScopedStyle(metadata: metadata, plain: !selfClosing && tokens.count == 1 && loop == nil && condition == nil && identity == nil) }
        tokens.append(.text(selfClosing ? " />" : ">", metadata: metadata))
        var opening: [Token] = []
        if let identity {
            guard let loop else { throw htmlDiagnostic(":key requires :for on the same element", at: metadata) }
            opening.append(.keyedOpen(loop: loop, key: identity, condition: condition, metadata: metadata))
        } else {
            if let loop { opening.append(.code("+for \(loop) {", metadata: metadata)) }
            if let condition { opening.append(.code("+if \(condition) {", metadata: metadata)) }
        }
        let directives = (loop == nil ? 0 : 1) + (condition == nil ? 0 : 1)
        // Top-level elements, including those passed into component slots, receive the scope attribute.
        if htmlElements.allSatisfy({ $0.name.hasPrefix(".") || $0.name.hasPrefix(":") }) {
            pendingRootClose = opening.count + tokens.count - 1
        }
        if selfClosing || Self.voidElements.contains(name) {
            return opening + tokens + closingDirectives(directives, keyed: identity != nil, metadata: metadata)
        }
        openHTMLElement(name, line: metadata.line, column: metadata.column, directives: directives, keyed: identity != nil, interpolateCurly: interpolateCurly)
        return opening + tokens
    }

    /// Collects static CSS for the build plugin's `ESWStyles`; the element itself is not emitted.
    private mutating func readScopedStyle(metadata: Metadata, plain: Bool) throws -> [Token] {
        guard plain else { throw htmlDiagnostic("<style :scoped> takes no other attributes or directives", at: metadata) }
        guard htmlElements.isEmpty else { throw htmlDiagnostic("<style :scoped> must be a top-level element", at: metadata) }
        guard scope != nil else {
            throw htmlDiagnostic("<style :scoped> needs a file template compiled by ESWBuildPlugin", at: metadata)
        }
        var css = ""
        while !isRawTextClose("style") {
            guard index < source.endIndex else { throw htmlDiagnostic("unclosed tag <style>", at: metadata) }
            guard !isEExBoundary else { throw htmlDiagnostic("<style :scoped> must contain static CSS") }
            css.append(advance())
        }
        for _ in 0..<"</style".count { advance() }
        skipWhitespace()
        guard peek() == ">" else { throw htmlDiagnostic("malformed closing tag") }
        advance()
        scopedStyles.append(css)
        return []
    }

    private func closingDirectives(_ count: Int, keyed: Bool, metadata: Metadata) -> [Token] {
        if keyed { return [.keyedClose(conditional: count == 2, metadata: metadata)] }
        return (0..<count).map { _ in .code("+}", metadata: metadata) }
    }
}
