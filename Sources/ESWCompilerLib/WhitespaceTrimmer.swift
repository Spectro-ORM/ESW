public enum WhitespaceTrimmer {

    /// Applies whitespace trimming to a token array per spec §7.2.
    ///
    /// For each `.code` token, if the preceding `.text` ends with `\n` + spaces/tabs
    /// and the following `.text` starts with spaces/tabs + `\n` (or is at EOF),
    /// those surrounding whitespace + newlines are trimmed.
    ///
    /// `.code` tokens whose content starts with `+` are exempt from trimming
    /// (the `+` is stripped from the content).
    public static func trim(_ tokens: [Token]) -> [Token] {
        var result = tokens
        var i = 0

        while i < result.count {
            guard case .code(let content, let metadata) = result[i] else {
                i += 1
                continue
            }

            // <%+ code %> — preserve whitespace, strip the `+` prefix
            if content.hasPrefix("+") {
                let trimmedContent = String(content.dropFirst()).trimmingLeadingWhitespace()
                result[i] = .code(trimmedContent, metadata: metadata)
                i += 1
                continue
            }

            // Strip optional `-` suffix (explicit trim, same as default)
            var codeContent = content
            if codeContent.hasSuffix("-") {
                codeContent = String(codeContent.dropLast()).trimmingTrailingWhitespace()
                result[i] = .code(codeContent, metadata: metadata)
            }

            // Trim surrounding whitespace — first/last lines in the file
            // are treated as matching the missing side.
            if i > 0 { trimTrailingLineWhitespace(&result, at: i - 1) }
            if i + 1 < result.count { trimLeadingLineWhitespace(&result, at: i + 1) }

            i += 1
        }

        // Remove empty text tokens left by trimming
        result.removeAll { token in
            if case .text(let s, _) = token, s.isEmpty {
                return true
            }
            return false
        }

        return result
    }

    // MARK: - Private helpers

    /// Trims trailing `[spaces/tabs]*\n` from a text token at the given index.
    /// Returns true if the pattern was found and trimmed.
    @discardableResult
    private static func trimTrailingLineWhitespace(_ tokens: inout [Token], at index: Int) -> Bool {
        guard case .text(var text, let metadata) = tokens[index] else { return false }

        // Find the last newline, check that everything after it is spaces/tabs
        guard let lastNewline = text.lastIndex(of: "\n") else {
            // No newline — check if the entire text is spaces/tabs (start of file)
            if text.allSatisfy({ $0 == " " || $0 == "\t" }) {
                tokens[index] = .text("", metadata: metadata)
                return true
            }
            return false
        }

        let afterNewline = text[text.index(after: lastNewline)...]
        if afterNewline.allSatisfy({ $0 == " " || $0 == "\t" }) {
            text = String(text[...lastNewline])
            tokens[index] = .text(text, metadata: metadata)
            return true
        }

        return false
    }

    /// Trims leading `[spaces/tabs]*\n` from a text token at the given index.
    /// Returns true if the pattern was found and trimmed.
    @discardableResult
    private static func trimLeadingLineWhitespace(_ tokens: inout [Token], at index: Int) -> Bool {
        guard case .text(var text, let metadata) = tokens[index] else { return false }

        // Find the first newline, check that everything before it is spaces/tabs
        guard let firstNewline = text.firstIndex(of: "\n") else {
            // No newline — check if the entire text is spaces/tabs (end of file)
            if text.allSatisfy({ $0 == " " || $0 == "\t" }) {
                tokens[index] = .text("", metadata: metadata)
                return true
            }
            return false
        }

        let beforeNewline = text[..<firstNewline]
        if beforeNewline.allSatisfy({ $0 == " " || $0 == "\t" }) {
            text = String(text[text.index(after: firstNewline)...])
            tokens[index] = .text(text, metadata: metadata)
            return true
        }

        return false
    }
}

extension String {
    func trimmingLeadingWhitespace() -> String {
        var start = startIndex
        while start < endIndex && (self[start] == " " || self[start] == "\t") {
            start = index(after: start)
        }
        return String(self[start...])
    }

    func trimmingTrailingWhitespace() -> String {
        var end = endIndex
        while end > startIndex {
            let prev = index(before: end)
            if self[prev] == " " || self[prev] == "\t" {
                end = prev
            } else {
                break
            }
        }
        return String(self[..<end])
    }
}
