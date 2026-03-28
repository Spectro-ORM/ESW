import Testing
@testable import ESWCompilerLib

/// Helper to tokenize and then trim.
private func tokenizeAndTrim(_ source: String, file: String = "test.esw") throws -> [Token] {
    var tokenizer = Tokenizer(source: source, file: file)
    let tokens = try tokenizer.tokenize()
    return WhitespaceTrimmer.trim(tokens)
}

/// Extract just the content strings and token types for easier assertion.
private enum TokenKind: Equatable {
    case text(String)
    case output(String)
    case rawOutput(String)
    case code(String)
    case comment(String)
    case assigns(String)
}

private func kinds(_ tokens: [Token]) -> [TokenKind] {
    tokens.map { token in
        switch token {
        case .text(let s, _): .text(s)
        case .output(let s, _): .output(s)
        case .rawOutput(let s, _): .rawOutput(s)
        case .code(let s, _): .code(s)
        case .comment(let s, _): .comment(s)
        case .assigns(let s, _): .assigns(s)
        }
    }
}

@Suite("WhitespaceTrimmer")
struct WhitespaceTrimmerTests {

    @Test func controlOnlyLineTrimmed() throws {
        // Spec §14: <% if x { %>\nhello\n<% } %>
        let tokens = try tokenizeAndTrim("<% if x { %>\nhello\n<% } %>")
        #expect(kinds(tokens) == [
            .code("if x {"),
            .text("hello\n"),
            .code("}"),
        ])
    }

    @Test func outputTagsNeverTrimmed() throws {
        let tokens = try tokenizeAndTrim("hello\n<%= name %>\nworld")
        #expect(kinds(tokens) == [
            .text("hello\n"),
            .output("name"),
            .text("\nworld"),
        ])
    }

    @Test func controlLineWithIndentation() throws {
        let tokens = try tokenizeAndTrim("<ul>\n  <% for item in items { %>\n  <li></li>\n  <% } %>\n</ul>")
        #expect(kinds(tokens) == [
            .text("<ul>\n"),
            .code("for item in items {"),
            .text("  <li></li>\n"),
            .code("}"),
            .text("</ul>"),
        ])
    }

    @Test func preserveWithPlusModifier() throws {
        let tokens = try tokenizeAndTrim("before\n<%+ someCode %>\nafter")
        #expect(kinds(tokens).contains(.code("someCode")))
        // Surrounding text should NOT be trimmed
        let textContents = kinds(tokens).compactMap { kind -> String? in
            if case .text(let s) = kind { return s }
            return nil
        }
        let combinedText = textContents.joined()
        #expect(combinedText.contains("\n"))
    }

    @Test func firstLineCode() throws {
        let tokens = try tokenizeAndTrim("<% if true { %>\nhello\n<% } %>")
        #expect(kinds(tokens) == [
            .code("if true {"),
            .text("hello\n"),
            .code("}"),
        ])
    }

    @Test func lastLineCode() throws {
        let tokens = try tokenizeAndTrim("hello\n<% end %>")
        #expect(kinds(tokens) == [
            .text("hello\n"),
            .code("end"),
        ])
    }

    @Test func noTrimWhenNotControlOnlyLine() throws {
        let tokens = try tokenizeAndTrim("before<% code %>after")
        #expect(kinds(tokens) == [
            .text("before"),
            .code("code"),
            .text("after"),
        ])
    }

    @Test func consecutiveCodeTags() throws {
        let tokens = try tokenizeAndTrim("<% a %>\n<% b %>\nhello")
        #expect(kinds(tokens) == [
            .code("a"),
            .code("b"),
            .text("hello"),
        ])
    }

    @Test func explicitTrimDash() throws {
        let tokens = try tokenizeAndTrim("<% code -%>\nhello")
        #expect(kinds(tokens).contains(.code("code")))
    }

    @Test func textOnlyNotTrimmed() throws {
        let tokens = try tokenizeAndTrim("just plain text\nwith newlines")
        #expect(kinds(tokens) == [.text("just plain text\nwith newlines")])
    }

    @Test func commentsNotTrimmed() throws {
        // Comments are not code tags — trimmer should not touch surrounding whitespace
        let tokens = try tokenizeAndTrim("before\n<%# a comment %>\nafter")
        #expect(kinds(tokens) == [
            .text("before\n"),
            .comment("a comment"),
            .text("\nafter"),
        ])
    }
}
