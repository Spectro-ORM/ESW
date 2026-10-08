/// Scans template text into located tokens, optionally validating HTML structure.
/// A tokenizer advances through its input; create a new value to scan it again.
public struct Tokenizer {
    let source: String
    let file: String
    var index: String.Index
    var line: Int = 1
    var column: Int = 1
    let syntax: TemplateSyntax
    var htmlElements: [HTMLElement] = []
    var htmlCommentMetadata: Metadata?
    /// The `data-esw` value for top-level elements when the template has `<style :scoped>`.
    let scope: String?
    /// CSS collected from `<style :scoped>` blocks, in source order.
    public internal(set) var scopedStyles: [String] = []
    var rootTagCloses: [Int] = []
    var pendingRootClose: Int?

    /// Creates a scanner, normalizing CRLF and CR line endings to LF.
    /// `file` is used for diagnostics; this initializer does not read a file.
    /// `scope` enables `<style :scoped>` in HTML-aware templates; inline templates pass nil.
    public init(source: String, file: String = "<anonymous>", syntax: TemplateSyntax = .esw, scope: String? = nil) {
        // Normalize line endings: \r\n → \n, bare \r → \n.
        // Swift treats \r\n as a single Character (grapheme cluster), so we
        // must work at the unicode scalar level.
        let src = Array(source.unicodeScalars)
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(src.count)
        var j = 0
        while j < src.count {
            if src[j] == "\r" {
                result.append("\n")
                // Skip \n after \r (CRLF pair)
                if j + 1 < src.count && src[j + 1] == "\n" {
                    j += 1
                }
            } else {
                result.append(src[j])
            }
            j += 1
        }
        let normalized = String(String.UnicodeScalarView(result))
        self.source = normalized
        self.file = file
        self.index = normalized.startIndex
        self.syntax = syntax
        self.scope = scope
    }

    /// Consumes the remaining input and returns its located tokens.
    /// - Throws: A tokenizer or HTML diagnostic for malformed template structure.
    public mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        var textBuffer = ""
        var textLine = line
        var textColumn = column

        while index < source.endIndex {
            if syntax == .hesw, let htmlTokens = try readHTMLToken() {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                tokens.append(contentsOf: htmlTokens)
                if let offset = pendingRootClose {
                    rootTagCloses.append(tokens.count - htmlTokens.count + offset)
                    pendingRootClose = nil
                }
                continue
            }
            // Check for `<%%` (escape open → literal `<%`)
            if peek() == "<" && peek(offset: 1) == "%" && peek(offset: 2) == "%" {
                if textBuffer.isEmpty {
                    textLine = line
                    textColumn = column
                }
                advance() // <
                advance() // %
                advance() // %
                textBuffer += "<%"
                continue
            }

            // Check for `%%>` (escape close → literal `%>`)
            if peek() == "%" && peek(offset: 1) == "%" && peek(offset: 2) == ">" {
                if textBuffer.isEmpty {
                    textLine = line
                    textColumn = column
                }
                advance() // %
                advance() // %
                advance() // >
                textBuffer += "%>"
                continue
            }

            // Check for `</:` (slot close tag, e.g. `</:header>`)
            if peek() == "<" && peek(offset: 1) == "/" && peek(offset: 2) == ":" {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // /
                advance() // :
                let name = try readValidatedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                skipWhitespace()
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance() // >
                if syntax == .hesw { try closeHTMLElement(":" + name) }
                tokens.append(.slotClose(name: name, metadata: Metadata(file: file, line: tagLine, column: tagColumn)))
                continue
            }

            // Check for `<:` (slot open tag, e.g. `<:header>`)
            if peek() == "<" && peek(offset: 1) == ":" {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // :
                let name = try readValidatedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                let metadata = Metadata(file: file, line: tagLine, column: tagColumn)
                if syntax == .hesw, htmlElements.last?.name.hasPrefix(".") != true {
                    throw htmlDiagnostic("named slots must be direct children of a component", at: metadata)
                }
                var attributes = try readComponentAttributes(tagLine: tagLine, tagColumn: tagColumn)
                let interpolateCurly = try consumeCurlyDirective(in: &attributes, metadata: metadata)
                let selfClosing = peek() == "/"
                if selfClosing { advance() }
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance()
                try TemplateValidation.validateBinding(in: attributes, selfClosing: selfClosing, metadata: metadata)
                if attributes.contains(where: { $0.key == ":key" }) {
                    throw htmlDiagnostic(":key is not supported on slots; use it on an element or component with :for", at: metadata)
                }
                if syntax == .hesw && !selfClosing {
                    openHTMLElement(":" + name, line: tagLine, column: tagColumn, interpolateCurly: interpolateCurly)
                }
                tokens.append(.slotOpen(name: name, attributes: attributes, selfClosing: selfClosing, metadata: metadata))
                continue
            }

            // Check for `</.` (component close tag, e.g. `</.card>`)
            if peek() == "<" && peek(offset: 1) == "/" && (peek(offset: 2) == "." || isQualifiedComponentTag(closing: true)) {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // /
                let local = peek() == "."
                if local { advance() }
                let name = try local ? readValidatedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                    : readQualifiedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                skipWhitespace()
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance() // >
                if syntax == .hesw { try closeHTMLElement("." + name) }
                tokens.append(.componentClose(name: name, metadata: Metadata(file: file, line: tagLine, column: tagColumn)))
                continue
            }

            // Check for `<.` (component open tag, e.g. `<.button>`, `<.card title="Hi" />`)
            if peek() == "<" && (peek(offset: 1) == "." || isQualifiedComponentTag(closing: false)) {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                let local = peek() == "."
                if local { advance() }
                let name = try local ? readValidatedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                    : readQualifiedComponentName(tagLine: tagLine, tagColumn: tagColumn)
                var attributes = try readComponentAttributes(tagLine: tagLine, tagColumn: tagColumn)
                let interpolateCurly = try consumeCurlyDirective(in: &attributes,
                    metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                skipWhitespace()
                let selfClosing: Bool
                if peek() == "/" && peek(offset: 1) == ">" {
                    advance() // /
                    advance() // >
                    selfClosing = true
                } else if peek() == ">" {
                    advance() // >
                    selfClosing = false
                } else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                try TemplateValidation.validateBinding(in: attributes, selfClosing: selfClosing,
                    metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                tokens.append(.componentTag(
                    name: name,
                    attributes: attributes,
                    selfClosing: selfClosing,
                    metadata: Metadata(file: file, line: tagLine, column: tagColumn)
                ))
                if syntax == .hesw && !selfClosing {
                    openHTMLElement("." + name, line: tagLine, column: tagColumn, interpolateCurly: interpolateCurly)
                }
                continue
            }

            // Check for `<%` (tag open)
            if peek() == "<" && peek(offset: 1) == "%" {
                // Flush text buffer
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }

                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // %

                guard index < source.endIndex else {
                    throw ESWTokenizerError.unterminatedTag(file: file, line: tagLine, column: tagColumn)
                }

                let token: Token

                if peek() == "!" && peek(offset: 1) == "-" && peek(offset: 2) == "-" {
                    advance() // !
                    advance() // -
                    advance() // -
                    let content = try readUntilCommentClose(tagLine: tagLine, tagColumn: tagColumn)
                    token = .comment(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                } else if peek() == "!" {
                    advance() // !
                    let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn)
                    token = .assigns(content, metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                } else if peek() == "#" {
                    advance() // #
                    let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn, swiftAware: false)
                    token = .comment(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                } else if peek() == "=" {
                    advance() // =
                    if peek() == "=" {
                        advance() // =
                        let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn)
                        token = .rawOutput(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                    } else {
                        let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn)
                        token = .output(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                    }
                } else {
                    let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn)
                    token = .code(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                }

                tokens.append(token)
                continue
            }

            // Regular character → accumulate in text buffer
            if textBuffer.isEmpty {
                textLine = line
                textColumn = column
            }
            textBuffer.append(advance())
        }

        // Flush remaining text
        if !textBuffer.isEmpty {
            tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
        }

        if let metadata = htmlCommentMetadata {
            throw htmlDiagnostic("unterminated HTML comment", at: metadata)
        }
        if let element = htmlElements.last {
            throw ESWHTMLDiagnostic(metadata: element.metadata, message: "unclosed tag <\(element.name)>")
        }
        if let scope, !scopedStyles.isEmpty {
            guard !rootTagCloses.isEmpty else {
                throw htmlDiagnostic("<style :scoped> needs a top-level HTML element to scope", at: Metadata(file: file, line: 1, column: 1))
            }
            for index in rootTagCloses {
                guard case .text(let close, let metadata) = tokens[index] else { continue }
                tokens[index] = .text(" data-esw=\"\(scope)\"" + close, metadata: metadata)
            }
        }
        return tokens
    }

    // MARK: - Private helpers

    func peek(offset: Int = 0) -> Character? {
        var idx = index
        for _ in 0..<offset {
            guard idx < source.endIndex else { return nil }
            idx = source.index(after: idx)
        }
        guard idx < source.endIndex else { return nil }
        return source[idx]
    }

    @discardableResult
    mutating func advance() -> Character {
        let c = source[index]
        index = source.index(after: index)
        if c == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        return c
    }

    /// Reads until the `--%>` close sequence for `<%!-- --%>` multi-line comments.
    /// Unlike `readUntilClose`, a bare `%>` does NOT terminate this — only `--%>` does.
    private mutating func readUntilCommentClose(tagLine: Int, tagColumn: Int) throws -> String {
        var content = ""
        while index < source.endIndex {
            if peek() == "-" && peek(offset: 1) == "-" && peek(offset: 2) == "%" && peek(offset: 3) == ">" {
                advance() // -
                advance() // -
                advance() // %
                advance() // >
                return content
            }
            content.append(advance())
        }
        throw ESWTokenizerError.unterminatedTag(file: file, line: tagLine, column: tagColumn)
    }

    func isQualifiedComponentTag(closing: Bool) -> Bool {
        var offset = closing ? 2 : 1
        guard peek() == "<", let first = peek(offset: offset), first.isUppercase else { return false }
        while let c = peek(offset: offset), c.isLetter || c.isNumber || c == "_" || c == "." {
            if c == "." { return true }
            offset += 1
        }
        return false
    }

    private mutating func readQualifiedComponentName(tagLine: Int, tagColumn: Int) throws -> String {
        var name = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" || c == "." { name.append(advance()) }
        let pieces = name.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count > 1, pieces.allSatisfy({ part in
            guard let first = part.first else { return false }
            return first.isLetter || first == "_"
        }) else {
            throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
        }
        return name
    }

    /// Reads a component name: letters, digits, hyphens (e.g. `button`, `user-card`).
    private mutating func readComponentName() -> String {
        var name = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "-" {
            name.append(advance())
        }
        return name
    }

    private mutating func readValidatedComponentName(tagLine: Int, tagColumn: Int) throws -> String {
        let name = readComponentName()
        guard let first = name.first, first.isLetter,
              !name.hasSuffix("-"), !name.contains("--") else {
            throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
        }
        return name
    }

    /// Skips any whitespace characters (space, tab, newline).
    mutating func skipWhitespace() {
        while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" {
            advance()
        }
    }

    /// The body-only interpolation directive is not a Swift component argument.
    private func consumeCurlyDirective(in attributes: inout [ComponentAttribute], metadata: Metadata) throws -> Bool {
        guard syntax == .hesw else { return true }
        let directives = attributes.filter { $0.key.lowercased() == "phx-no-curly-interpolation" }
        guard !directives.isEmpty else { return true }
        guard directives.count == 1, directives[0].value == nil else {
            throw htmlDiagnostic("phx-no-curly-interpolation is a single bare compile-time attribute", at: metadata)
        }
        attributes.removeAll { $0.key.lowercased() == "phx-no-curly-interpolation" }
        return false
    }

    /// Reads zero or more component attributes until `/>` or `>`.
    private mutating func readComponentAttributes(tagLine: Int, tagColumn: Int) throws -> [ComponentAttribute] {
        var attrs: [ComponentAttribute] = []
        while true {
            skipWhitespace()
            guard let c = peek() else {
                throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
            }
            // End of attributes
            if c == ">" || (c == "/" && peek(offset: 1) == ">") { break }
            // Read attribute key
            let key = readAttributeKey()
            guard let first = key.first, first.isLetter || first == "_" || (syntax == .hesw && first == ":"),
                  !attrs.contains(where: { $0.key.replacingHyphens() == key.replacingHyphens() }) else {
                throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
            }
            let afterKey = index
            let afterKeyLine = line
            let afterKeyColumn = column
            skipWhitespace()
            // Check for value
            if peek() == "=" {
                advance() // =
                skipWhitespace()
                if peek() == "\"" || peek() == "'" {
                    // String literal: attr="value"
                    let quote = advance()
                    let value = try readStringAttributeValue(quote: quote, tagLine: tagLine, tagColumn: tagColumn)
                    attrs.append(ComponentAttribute(key: key, value: .string(value)))
                } else if peek() == "{" {
                    // Expression: attr={swiftExpr}
                    advance() // {
                    let expr = try readExpressionAttributeValue(tagLine: tagLine, tagColumn: tagColumn)
                    attrs.append(ComponentAttribute(key: key, value: .expression(expr)))
                } else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
            } else {
                // Bare boolean attribute
                attrs.append(ComponentAttribute(key: key, value: nil))
                // Keep the separator available for the next attribute.
                index = afterKey
                line = afterKeyLine
                column = afterKeyColumn
            }
            if key.hasPrefix(":") {
                guard (key == ":if" || key == ":for" || key == ":let" || key == ":key"), case .expression = attrs.last?.value else {
                    throw htmlDiagnostic("component directive '\(key)' requires {expression}")
                }
            }
            if let next = peek(), !next.isWhitespace, next != ">", next != "/" {
                throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
            }
        }
        if attrs.contains(where: { $0.key == ":key" }), !attrs.contains(where: { $0.key == ":for" }) {
            throw htmlDiagnostic(":key requires :for on the same component or element",
                                 at: Metadata(file: file, line: tagLine, column: tagColumn))
        }
        return attrs
    }

    /// Reads an attribute key: letters, digits, hyphens, underscores.
    private mutating func readAttributeKey() -> String {
        var key = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "-" || c == "_" || (syntax == .hesw && c == ":") {
            key.append(advance())
        }
        return key
    }

    /// Reads characters until a closing `"`, consuming it. Returns content without quotes.
    private mutating func readStringAttributeValue(quote: Character, tagLine: Int, tagColumn: Int) throws -> String {
        var value = ""
        while let c = peek(), c != quote {
            value.append(advance())
        }
        guard peek() == quote else {
            throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
        }
        advance()
        return value
    }

    /// Reads characters until a matching `}`, consuming it. Handles nested `{}`.
    mutating func readExpressionAttributeValue(tagLine: Int, tagColumn: Int) throws -> String {
        var expr = ""
        var depth = 1
        while index < source.endIndex {
            if let end = SwiftLexicalScanner.opaqueEnd(in: source, at: index) {
                while index < end { expr.append(advance()) }
                continue
            }
            let c = advance()
            if c == "{" {
                depth += 1
                expr.append(c)
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    guard !expr.trimmingWhitespace().isEmpty else {
                        throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                    }
                    return expr
                }
                expr.append(c)
            } else {
                expr.append(c)
            }
        }
        throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
    }

    private mutating func readUntilClose(tagLine: Int, tagColumn: Int, swiftAware: Bool = true) throws -> String {
        var content = ""
        while index < source.endIndex {
            if swiftAware, let end = SwiftLexicalScanner.opaqueEnd(in: source, at: index) {
                while index < end { content.append(advance()) }
                continue
            }
            // Check for `%%>` (escaped close → literal `%>` in content)
            if peek() == "%" && peek(offset: 1) == "%" && peek(offset: 2) == ">" {
                advance() // %
                advance() // %
                advance() // >
                content += "%>"
                continue
            }
            if peek() == "%" && peek(offset: 1) == ">" {
                advance() // %
                advance() // >
                return content
            }
            content.append(advance())
        }
        throw ESWTokenizerError.unterminatedTag(file: file, line: tagLine, column: tagColumn)
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var start = startIndex
        while start < endIndex && (self[start] == " " || self[start] == "\t" || self[start] == "\n" || self[start] == "\r") {
            start = index(after: start)
        }
        var end = endIndex
        while end > start {
            let prev = index(before: end)
            if self[prev] == " " || self[prev] == "\t" || self[prev] == "\n" || self[prev] == "\r" {
                end = prev
            } else {
                break
            }
        }
        return String(self[start..<end])
    }
}
