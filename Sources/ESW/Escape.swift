/// Marks pre-rendered HTML as safe for embedding via `<%= %>`.
/// Wraps the content in `ESWValue.safe` so `ESW.escape()` passes it through
/// without double-escaping.
///
/// Usage in templates:
/// ```html
/// <%= render(_renderCardBuffer(user: user)) %>
/// ```
public func render(_ content: String) -> ESWValue {
    .safe(content)
}

public enum ESW {
    public static func escape(_ value: Any?) -> String {
        guard let value = unwrapped(value) else { return "" }
        let string: String
        switch value {
        case let s as String:
            string = s
        case let n as Int:
            return String(n)
        case let n as Double:
            return String(n)
        case let b as Bool:
            return b ? "true" : "false"
        case let esw as ESWValue:
            switch esw {
            case .safe(let s):
                return s
            case .unsafe(let s):
                string = s
            }
        default:
            string = String(describing: value)
        }
        // Match HTML delimiters as scalars, not extended grapheme clusters:
        // a quote followed by a combining mark must still be escaped.
        guard string.utf8.contains(where: { $0 == 34 || $0 == 38 || $0 == 39 || $0 == 60 || $0 == 62 }) else { return string }
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for c in string.unicodeScalars {
            switch c {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.unicodeScalars.append(c)
            }
        }
        return result
    }
}

private protocol OptionalValue {
    var wrappedValue: Any? { get }
}

extension Optional: OptionalValue {
    fileprivate var wrappedValue: Any? { map { $0 as Any } }
}

extension ESW {
    static func unwrapped(_ value: Any?) -> Any? {
        guard let value else { return nil }
        if let optional = value as? any OptionalValue {
            return unwrapped(optional.wrappedValue)
        }
        return value
    }
}
