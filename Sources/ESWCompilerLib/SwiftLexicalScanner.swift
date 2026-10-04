/// Skips Swift strings and comments when looking for template delimiters.
enum SwiftLexicalScanner {
    static func opaqueEnd(in source: String, at start: String.Index) -> String.Index? {
        let tail = source[start...]
        if tail.hasPrefix("//") {
            return tail.firstIndex(of: "\n") ?? source.endIndex
        }
        if tail.hasPrefix("/*") {
            var cursor = source.index(start, offsetBy: 2)
            var depth = 1
            while cursor < source.endIndex {
                if source[cursor...].hasPrefix("/*") {
                    depth += 1
                    cursor = source.index(cursor, offsetBy: 2)
                } else if source[cursor...].hasPrefix("*/") {
                    depth -= 1
                    cursor = source.index(cursor, offsetBy: 2)
                    if depth == 0 { return cursor }
                } else {
                    cursor = source.index(after: cursor)
                }
            }
            return source.endIndex
        }

        var cursor = start
        while cursor < source.endIndex, source[cursor] == "#" {
            cursor = source.index(after: cursor)
        }
        let hashes = String(source[start..<cursor])
        guard cursor < source.endIndex, source[cursor] == "\"" else { return nil }
        let quotes = source[cursor...].hasPrefix("\"\"\"") ? "\"\"\"" : "\""
        cursor = source.index(cursor, offsetBy: quotes.count)
        let closing = quotes + hashes
        let escape = "\\" + hashes
        while cursor < source.endIndex {
            if source[cursor...].hasPrefix(closing) {
                return source.index(cursor, offsetBy: closing.count)
            }
            if source[cursor...].hasPrefix(escape) {
                cursor = source.index(cursor, offsetBy: escape.count)
                guard cursor < source.endIndex else { break }
                if source[cursor] == "(" {
                    cursor = interpolationEnd(in: source, at: cursor)
                } else {
                    cursor = source.index(after: cursor)
                }
            } else {
                cursor = source.index(after: cursor)
            }
        }
        return source.endIndex
    }

    private static func interpolationEnd(in source: String, at start: String.Index) -> String.Index {
        var cursor = source.index(after: start)
        var depth = 1
        while cursor < source.endIndex {
            if let end = opaqueEnd(in: source, at: cursor) {
                cursor = end
                continue
            }
            let character = source[cursor]
            cursor = source.index(after: cursor)
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return source.endIndex
    }
}
