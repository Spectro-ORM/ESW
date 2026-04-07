public struct Tokenizer {
    private let source: String
    private let file: String
    private var index: String.Index
    private var line: Int = 1
    private var column: Int = 1

    public init(source: String, file: String = "<anonymous>") {
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
    }

    public mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        var textBuffer = ""
        var textLine = line
        var textColumn = column

        while index < source.endIndex {
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
                let name = readComponentName()
                skipWhitespace()
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance() // >
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
                let name = readComponentName()
                skipWhitespace()
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance() // >
                tokens.append(.slotOpen(name: name, metadata: Metadata(file: file, line: tagLine, column: tagColumn)))
                continue
            }

            // Check for `</.` (component close tag, e.g. `</.card>`)
            if peek() == "<" && peek(offset: 1) == "/" && peek(offset: 2) == "." {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // /
                advance() // .
                let name = readComponentName()
                skipWhitespace()
                guard peek() == ">" else {
                    throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
                }
                advance() // >
                tokens.append(.componentClose(name: name, metadata: Metadata(file: file, line: tagLine, column: tagColumn)))
                continue
            }

            // Check for `<.` (component open tag, e.g. `<.button>`, `<.card title="Hi" />`)
            if peek() == "<" && peek(offset: 1) == "." {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer, metadata: Metadata(file: file, line: textLine, column: textColumn)))
                    textBuffer = ""
                }
                let tagLine = line
                let tagColumn = column
                advance() // <
                advance() // .
                let name = readComponentName()
                let attributes = try readComponentAttributes(tagLine: tagLine, tagColumn: tagColumn)
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
                tokens.append(.componentTag(
                    name: name,
                    attributes: attributes,
                    selfClosing: selfClosing,
                    metadata: Metadata(file: file, line: tagLine, column: tagColumn)
                ))
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
                    token = .assigns(content.trimmingWhitespace(), metadata: Metadata(file: file, line: tagLine, column: tagColumn))
                } else if peek() == "#" {
                    advance() // #
                    let content = try readUntilClose(tagLine: tagLine, tagColumn: tagColumn)
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

        return tokens
    }

    // MARK: - Private helpers

    private func peek(offset: Int = 0) -> Character? {
        var idx = index
        for _ in 0..<offset {
            guard idx < source.endIndex else { return nil }
            idx = source.index(after: idx)
        }
        guard idx < source.endIndex else { return nil }
        return source[idx]
    }

    @discardableResult
    private mutating func advance() -> Character {
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

    /// Reads a component name: letters, digits, hyphens (e.g. `button`, `user-card`).
    private mutating func readComponentName() -> String {
        var name = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "-" {
            name.append(advance())
        }
        return name
    }

    /// Skips any whitespace characters (space, tab, newline).
    private mutating func skipWhitespace() {
        while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" {
            advance()
        }
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
            guard !key.isEmpty else {
                throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
            }
            skipWhitespace()
            // Check for value
            if peek() == "=" {
                advance() // =
                if peek() == "\"" {
                    // String literal: attr="value"
                    advance() // opening "
                    let value = readStringAttributeValue()
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
            }
        }
        return attrs
    }

    /// Reads an attribute key: letters, digits, hyphens, underscores.
    private mutating func readAttributeKey() -> String {
        var key = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "-" || c == "_" {
            key.append(advance())
        }
        return key
    }

    /// Reads characters until a closing `"`, consuming it. Returns content without quotes.
    private mutating func readStringAttributeValue() -> String {
        var value = ""
        while let c = peek(), c != "\"" {
            value.append(advance())
        }
        if peek() == "\"" { advance() } // closing "
        return value
    }

    /// Reads characters until a matching `}`, consuming it. Handles nested `{}`.
    private mutating func readExpressionAttributeValue(tagLine: Int, tagColumn: Int) throws -> String {
        var expr = ""
        var depth = 1
        while index < source.endIndex {
            let c = advance()
            if c == "{" {
                depth += 1
                expr.append(c)
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return expr }
                expr.append(c)
            } else {
                expr.append(c)
            }
        }
        throw ESWTokenizerError.malformedComponentTag(file: file, line: tagLine, column: tagColumn)
    }

    private mutating func readUntilClose(tagLine: Int, tagColumn: Int) throws -> String {
        var content = ""
        while index < source.endIndex {
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
