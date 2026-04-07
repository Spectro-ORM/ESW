import Testing
@testable import ESWCompilerLib

/// Helper to tokenize a string with a default filename.
private func tokenize(_ source: String, file: String = "test.esw") throws -> [Token] {
    var tokenizer = Tokenizer(source: source, file: file)
    return try tokenizer.tokenize()
}

@Suite("Tokenizer")
struct TokenizerTests {

    // MARK: - Pure text

    @Test func pureText() throws {
        let tokens = try tokenize("hello world")
        #expect(tokens == [.text("hello world", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Output tag

    @Test func outputTag() throws {
        let tokens = try tokenize("<%= user.name %>")
        #expect(tokens == [.output("user.name", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Raw output tag

    @Test func rawOutputTag() throws {
        let tokens = try tokenize("<%== rawHTML %>")
        #expect(tokens == [.rawOutput("rawHTML", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Execution tag

    @Test func executionTag() throws {
        let tokens = try tokenize("<% if x { %>")
        #expect(tokens == [.code("if x {", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Comment tag

    @Test func commentTag() throws {
        let tokens = try tokenize("<%# this is a comment %>")
        #expect(tokens == [.comment("this is a comment", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Assigns block

    @Test func assignsBlock() throws {
        let tokens = try tokenize("<%!\nvar user: User\n%>")
        #expect(tokens == [.assigns("var user: User", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Delimiter escape

    @Test func delimiterEscape() throws {
        let tokens = try tokenize("show <%% tag %%>")
        #expect(tokens == [.text("show <% tag %>", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Mixed content

    @Test func mixedContent() throws {
        let tokens = try tokenize("<h1><%= title %></h1>")
        #expect(tokens == [
            .text("<h1>", metadata: Metadata(file: "test.esw", line: 1, column: 1)),
            .output("title", metadata: Metadata(file: "test.esw", line: 1, column: 5)),
            .text("</h1>", metadata: Metadata(file: "test.esw", line: 1, column: 17)),
        ])
    }

    // MARK: - Multiline — line tracking

    @Test func multilineLineTracking() throws {
        let tokens = try tokenize("<p>\n<%= name %>\n</p>")
        #expect(tokens == [
            .text("<p>\n", metadata: Metadata(file: "test.esw", line: 1, column: 1)),
            .output("name", metadata: Metadata(file: "test.esw", line: 2, column: 1)),
            .text("\n</p>", metadata: Metadata(file: "test.esw", line: 2, column: 12)),
        ])
    }

    // MARK: - Unterminated tag — error

    @Test func unterminatedTag() throws {
        #expect(throws: ESWTokenizerError.unterminatedTag(file: "test.esw", line: 1, column: 1)) {
            try tokenize("<% oops")
        }
    }

    // MARK: - Empty source

    @Test func emptySource() throws {
        let tokens = try tokenize("")
        #expect(tokens.isEmpty)
    }

    // MARK: - Multiple tags

    @Test func multipleTags() throws {
        let tokens = try tokenize("<%= a %><%= b %>")
        #expect(tokens == [
            .output("a", metadata: Metadata(file: "test.esw", line: 1, column: 1)),
            .output("b", metadata: Metadata(file: "test.esw", line: 1, column: 9)),
        ])
    }

    // MARK: - Code tag with no spaces

    @Test func codeTagNoSpaces() throws {
        let tokens = try tokenize("<%x%>")
        #expect(tokens == [.code("x", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Assigns with multiple vars

    @Test func assignsMultipleVars() throws {
        let tokens = try tokenize("<%!\nvar user: User\nvar posts: [Post]\n%>")
        #expect(tokens == [
            .assigns("var user: User\nvar posts: [Post]", metadata: Metadata(file: "test.esw", line: 1, column: 1)),
        ])
    }

    // MARK: - Tag at EOF (unterminated after type char)

    @Test func unterminatedAfterEquals() throws {
        #expect(throws: ESWTokenizerError.unterminatedTag(file: "test.esw", line: 1, column: 1)) {
            try tokenize("<%= oops")
        }
    }

    // MARK: - Escaped percent inside tag content

    @Test func escapedPercentInsideTag() throws {
        // %%> inside a tag should produce literal %>
        let tokens = try tokenize("<%= x %%> + 1 %>")
        #expect(tokens == [.output("x %> + 1", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    // MARK: - Multi-line comment <%!-- --%>

    @Test func multiLineComment() throws {
        let tokens = try tokenize("<%!-- this is a comment --%>")
        #expect(tokens == [.comment("this is a comment", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func multiLineCommentSpansLines() throws {
        let tokens = try tokenize("<%!--\nline one\nline two\n--%>")
        #expect(tokens == [.comment("line one\nline two", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func multiLineCommentContainsPercentClose() throws {
        // The key differentiator: %> inside <%!-- --%> does NOT terminate the comment
        let tokens = try tokenize("<%!-- has %> inside --%>")
        #expect(tokens == [.comment("has %> inside", metadata: Metadata(file: "test.esw", line: 1, column: 1))])
    }

    @Test func multiLineCommentUnterminated() throws {
        #expect(throws: ESWTokenizerError.unterminatedTag(file: "test.esw", line: 1, column: 1)) {
            try tokenize("<%!-- oops no close")
        }
    }

    @Test func multiLineCommentWithSurroundingText() throws {
        let tokens = try tokenize("before<%!-- hidden --%>after")
        #expect(tokens == [
            .text("before", metadata: Metadata(file: "test.esw", line: 1, column: 1)),
            .comment("hidden", metadata: Metadata(file: "test.esw", line: 1, column: 7)),
            .text("after", metadata: Metadata(file: "test.esw", line: 1, column: 24)),
        ])
    }

    // MARK: - Slot tags

    @Test func slotOpen() throws {
        let tokens = try tokenize("<:header>")
        #expect(tokens.count == 1)
        guard case .slotOpen(let name, _) = tokens[0] else {
            Issue.record("Expected slotOpen")
            return
        }
        #expect(name == "header")
    }

    @Test func slotClose() throws {
        let tokens = try tokenize("</:header>")
        #expect(tokens.count == 1)
        guard case .slotClose(let name, _) = tokens[0] else {
            Issue.record("Expected slotClose")
            return
        }
        #expect(name == "header")
    }

    @Test func slotWithHyphenatedName() throws {
        let tokens = try tokenize("<:top-bar>content</:top-bar>")
        #expect(tokens.count == 3)
        guard case .slotOpen(let name, _) = tokens[0] else {
            Issue.record("Expected slotOpen")
            return
        }
        #expect(name == "top-bar")
        guard case .text(let text, _) = tokens[1] else {
            Issue.record("Expected text")
            return
        }
        #expect(text == "content")
        guard case .slotClose(let closeName, _) = tokens[2] else {
            Issue.record("Expected slotClose")
            return
        }
        #expect(closeName == "top-bar")
    }

    @Test func slotInsideComponent() throws {
        let tokens = try tokenize("<.card><:body>Hello</:body></.card>")
        #expect(tokens.count == 5)
        guard case .componentTag(let name, _, _, _) = tokens[0] else {
            Issue.record("Expected componentTag")
            return
        }
        #expect(name == "card")
        guard case .slotOpen(let slotName, _) = tokens[1] else {
            Issue.record("Expected slotOpen")
            return
        }
        #expect(slotName == "body")
        guard case .text(let text, _) = tokens[2] else {
            Issue.record("Expected text")
            return
        }
        #expect(text == "Hello")
        guard case .slotClose(let closeName, _) = tokens[3] else {
            Issue.record("Expected slotClose")
            return
        }
        #expect(closeName == "body")
        guard case .componentClose(let closeCompName, _) = tokens[4] else {
            Issue.record("Expected componentClose")
            return
        }
        #expect(closeCompName == "card")
    }
}
