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
        guard let value else { return "" }
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
        var result = ""
        result.reserveCapacity(string.count)
        for c in string {
            switch c {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(c)
            }
        }
        return result
    }
}
