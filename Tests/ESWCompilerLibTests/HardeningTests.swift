import Testing
@testable import ESWCompilerLib

/// Helper to tokenize a string with a default filename.
private func tokenize(_ source: String, file: String = "test.esw") throws -> [Token] {
    var tokenizer = Tokenizer(source: source, file: file)
    return try tokenizer.tokenize()
}

/// Full pipeline helper: source → tokens → trim → parse assigns → generate.
private func generate(
    _ source: String,
    filename: String = "test.esw",
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

@Suite("Hardening")
struct HardeningTests {

    // MARK: - Raw String Hash Escalation

    @Test func textContainingQuoteHash() throws {
        // Template text: <p>Use "# for headers</p>
        // The "# sequence would break a single-hash raw string literal
        let source = "<p>Use \"# for headers</p>"
        let output = try generate(source, filename: "test.esw")
        // Must escalate to ##"..."## to avoid premature close
        #expect(output.contains("##\""))
    }

    @Test func textContainingHashQuote() throws {
        // Template text: <p>Color #"red"</p>
        let source = "<p>Color #\"red\"</p>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("##\""))
    }

    @Test func textContainingDoubleHashQuote() throws {
        // Template text: <p>##"test</p>
        let source = "<p>##\"test</p>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("###\""))
    }

    @Test func normalTextUsesOneHash() throws {
        let output = try generate("<p>Hello World</p>", filename: "test.esw")
        #expect(output.contains("#\"<p>Hello World</p>\"#"))
    }

    // MARK: - Backslash Sequences

    @Test func backslashNInText() throws {
        // Template source has literal backslash-n
        let source = "<p>line1\\nline2</p>"
        let output = try generate(source, filename: "test.esw")
        // Raw strings preserve backslashes literally
        #expect(output.contains("\\n"))
    }

    @Test func backslashTInText() throws {
        let source = "<p>\\t indented</p>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("\\t"))
    }

    @Test func backslashInURL() throws {
        let source = "<a href=\"C:\\Users\\file\">link</a>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("\\Users\\file"))
    }

    // MARK: - Empty Tags

    @Test func emptyOutputTag() throws {
        let tokens = try tokenize("<%= %>")
        #expect(tokens == [.output("", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func emptyCodeTag() throws {
        let tokens = try tokenize("<% %>")
        #expect(tokens == [.code("", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func emptyCommentTag() throws {
        let tokens = try tokenize("<%# %>")
        #expect(tokens == [.comment("", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func emptyAssignsTag() throws {
        let tokens = try tokenize("<%! %>")
        #expect(tokens == [.assigns("", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func emptyAssignsProducesNoParams() throws {
        let output = try generate("<%! %>\n<p>hello</p>", filename: "test.esw")
        #expect(output.contains("func renderTest("))
        #expect(output.contains("conn: Connection"))
    }

    // MARK: - Nested Delimiters

    @Test func nestedOpenDelimiterInString() throws {
        let source = "<% let x = \"<%= \" %>"
        let tokens = try tokenize(source)
        #expect(tokens.count == 1)
        if case .code(let code, _) = tokens[0] {
            #expect(code == "let x = \"<%= \"")
        } else {
            Issue.record("Expected code token")
        }
    }

    @Test func percentGreaterThanInStringLiteralKnownLimitation() throws {
        // Known limitation: %> inside a Swift string literal terminates the tag early.
        let source = "<% let x = \"%>\" %>"
        let tokens = try tokenize(source)
        #expect(tokens.count >= 1)
        if case .code(let code, _) = tokens[0] {
            #expect(code == "let x = \"")
        } else {
            Issue.record("Expected code token")
        }
    }

    // MARK: - UTF-8 Multi-byte Characters

    @Test func multiByteTextPreserved() throws {
        let tokens = try tokenize("<p>Héllo 世界 🌍</p>")
        #expect(tokens == [.text("<p>Héllo 世界 🌍</p>", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func multiByteColumnTracking() throws {
        let tokens = try tokenize("🌍<%= x %>")
        #expect(tokens.count == 2)
        if case .text(_, let meta) = tokens[0] {
            #expect(meta.column == 1)
        }
        if case .output(_, let meta) = tokens[1] {
            #expect(meta.column == 2)
        }
    }

    @Test func multiByteInExpression() throws {
        let tokens = try tokenize("<%= \"café\" %>")
        if case .output(let expr, _) = tokens[0] {
            #expect(expr == "\"café\"")
        }
    }

    @Test func cjkAndEmojiInGenerated() throws {
        let output = try generate("<p>日本語 🎉</p>", filename: "test.esw")
        #expect(output.contains("日本語 🎉"))
    }

    // MARK: - Windows Line Endings

    @Test func windowsLineEndings() throws {
        // \r\n is normalized to \n by the tokenizer
        let tokens = try tokenize("<p>\r\n<%= name %>\r\n</p>")
        #expect(tokens.count == 3)
        if case .output(_, let meta) = tokens[1] {
            #expect(meta.line == 2)
        }
        // Text tokens should not contain \r
        if case .text(let text, _) = tokens[0] {
            #expect(!text.contains("\r"))
        }
    }

    @Test func crlfInAssigns() throws {
        let source = "<%!\r\nvar name: String\r\n%>\r\n<p><%= name %></p>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("name: String"))
    }

    // MARK: - Assigns Error Cases

    @Test func unterminatedAssignsBlock() throws {
        #expect(throws: ESWTokenizerError.self) {
            try tokenize("<%!\nvar x: Int\n")
        }
    }

    @Test func multipleAssignsBlocksThrows() throws {
        let source = "<%!\nvar x: Int\n%>\n<%!\nvar y: String\n%>"
        #expect(throws: ESWAssignsError.self) {
            let _ = try generate(source, filename: "test.esw")
        }
    }

    // MARK: - Swift Keyword Parameter Names

    @Test func classParameterEscaped() throws {
        let source = "<%!\nvar class: String\n%>\n<p>hello</p>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("`class`: String"))
    }

    @Test func selfParameterEscaped() throws {
        let source = "<%!\nvar self: String\n%>\nhello"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("`self`: String"))
    }

    @Test func nonKeywordNotEscaped() throws {
        let source = "<%!\nvar name: String\n%>\nhello"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("name: String"))
        #expect(!output.contains("`name`"))
    }

    @Test func keywordInPartialBufferAndConn() throws {
        let source = "<%!\nvar `import`: String\n%>\nhello"
        let output = try generate(source, filename: "_widget.esw")
        #expect(output.contains("`import`: String"))
        let lines = output.split(separator: "\n")
        let funcLines = lines.filter { $0.contains("`import`") }
        #expect(funcLines.count >= 2)
    }

    @Test func allKeywordsEscaped() throws {
        let keywords = ["class", "struct", "enum", "protocol", "func", "var", "let",
                        "return", "if", "else", "for", "while", "switch", "case",
                        "default", "break", "continue", "in", "is", "as", "true",
                        "false", "nil", "guard", "where", "self", "Self"]
        for kw in keywords {
            #expect(CodeGenerator.escapedParamName(kw) == "`\(kw)`", "Expected \(kw) to be escaped")
        }
    }

    @Test func nonKeywordsNotEscaped() throws {
        let nonKeywords = ["name", "title", "user", "count", "items"]
        for word in nonKeywords {
            #expect(CodeGenerator.escapedParamName(word) == word, "Expected \(word) NOT to be escaped")
        }
    }

    // MARK: - Empty Text After Trimming

    @Test func emptyTextTokensSkipped() throws {
        let output = try generate("<% if true { %>\n<% } %>", filename: "test.esw")
        let lines = output.split(separator: "\n")
        let emptyAppends = lines.filter { $0.contains("_buf += #\"\"#") }
        #expect(emptyAppends.isEmpty)
    }

    // MARK: - Large Input

    @Test func largeTextBlock() throws {
        let chunk = "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>\n"
        let largeInput = String(repeating: chunk, count: 100)
        let output = try generate(largeInput, filename: "large.esw")
        #expect(output.contains("func renderLarge("))
        #expect(output.contains("return conn.html(_buf)"))
    }

    // MARK: - Multi-line Text in Raw Strings

    @Test func textWithEmbeddedNewlines() throws {
        let source = "<div>\n  <p>hello</p>\n</div>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("<div>\n  <p>hello</p>\n</div>"))
    }

    @Test func textWithMixedNewlinesAndTags() throws {
        let source = "<header>\n  <h1><%= title %></h1>\n</header>"
        let output = try generate(source, filename: "test.esw")
        #expect(output.contains("ESW.escape(title)"))
    }
}
