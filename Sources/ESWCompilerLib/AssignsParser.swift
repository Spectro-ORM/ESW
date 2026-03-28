public struct Parameter: Equatable, Sendable {
    public let name: String
    public let type: String
    public let defaultValue: String?

    public init(name: String, type: String, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }
}

public enum AssignsParser {

    /// Validates that the assigns token (if any) is the first non-text token, then
    /// parses its content into parameters.
    public static func parse(tokens: [Token], file: String) throws -> [Parameter] {
        var foundPriorContent = false
        var assignsContent: String?
        var assignsLine = 1

        for token in tokens {
            switch token {
            case .assigns(let content, let metadata):
                if foundPriorContent || assignsContent != nil {
                    throw ESWAssignsError.assignsNotFirst(file: file, line: metadata.line)
                }
                assignsContent = content
                assignsLine = metadata.line
            case .text(let s, _):
                // Only whitespace text before assigns is allowed
                if !s.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
                    foundPriorContent = true
                }
            default:
                foundPriorContent = true
            }
        }

        guard let content = assignsContent else {
            return []
        }

        return try parseDeclarations(content, file: file, startLine: assignsLine)
    }

    /// Parses the raw assigns content string into Parameter values.
    /// Each non-blank line should be `var name: Type` or `var name: Type = default`.
    private static func parseDeclarations(_ content: String, file: String, startLine: Int) throws -> [Parameter] {
        var parameters: [Parameter] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingWhitespaceChars()
            if trimmed.isEmpty { continue }

            guard let param = parseDeclaration(String(trimmed)) else {
                throw ESWAssignsError.invalidDeclaration(
                    file: file,
                    line: startLine + offset,
                    text: String(trimmed)
                )
            }
            parameters.append(param)
        }

        return parameters
    }

    /// Parses a single `var name: Type` or `var name: Type = default` declaration.
    private static func parseDeclaration(_ line: String) -> Parameter? {
        var remaining = line[...]

        // Must start with "var "
        guard remaining.hasPrefix("var ") else { return nil }
        remaining = remaining.dropFirst(4)

        // Skip whitespace
        remaining = remaining.drop { $0 == " " || $0 == "\t" }

        // Read the name (up to `:`)
        guard let colonIndex = remaining.firstIndex(of: ":") else { return nil }
        let name = remaining[..<colonIndex].trimmingWhitespaceChars()
        guard !name.isEmpty else { return nil }

        remaining = remaining[remaining.index(after: colonIndex)...]
        remaining = remaining.drop { $0 == " " || $0 == "\t" }

        // Check for default value
        if let equalsIndex = findTopLevelEquals(in: remaining) {
            let type = remaining[..<equalsIndex].trimmingWhitespaceChars()
            let defaultValue = remaining[remaining.index(after: equalsIndex)...].trimmingWhitespaceChars()
            guard !type.isEmpty, !defaultValue.isEmpty else { return nil }
            return Parameter(name: String(name), type: String(type), defaultValue: String(defaultValue))
        } else {
            let type = String(remaining).trimmingWhitespaceChars()
            guard !type.isEmpty else { return nil }
            return Parameter(name: String(name), type: String(type))
        }
    }

    /// Finds the `=` that separates type from default value, respecting bracket nesting.
    /// e.g. in `[String: Int] = [:]`, the `:` in `[String: Int]` shouldn't confuse us,
    /// and the `=` after the `]` is what we want.
    private static func findTopLevelEquals(in str: Substring) -> Substring.Index? {
        var depth = 0
        for i in str.indices {
            switch str[i] {
            case "[", "(", "<":
                depth += 1
            case "]", ")", ">":
                depth -= 1
            case "=" where depth == 0:
                return i
            default:
                break
            }
        }
        return nil
    }
}

extension StringProtocol {
    func trimmingWhitespaceChars() -> String {
        var start = startIndex
        while start < endIndex && (self[start] == " " || self[start] == "\t") {
            start = index(after: start)
        }
        var end = endIndex
        while end > start {
            let prev = index(before: end)
            if self[prev] == " " || self[prev] == "\t" {
                end = prev
            } else {
                break
            }
        }
        return String(self[start..<end])
    }
}
