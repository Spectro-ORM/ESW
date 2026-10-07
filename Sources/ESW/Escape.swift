/// Marks pre-rendered HTML as safe for embedding via `<%= %>`.
/// Wraps the content in `ESWValue.safe` so `ESW.escape()` passes it through
/// without double-escaping.
///
/// Usage in templates:
/// ```html
/// <%= render(_renderCardBuffer(user: user)) %>
/// ```
///
/// This function does not sanitize HTML. Use it only for output from a trusted
/// renderer or content whose trust policy your application has established.
public func render(_ content: String) -> ESWValue {
    .safe(content)
}

/// Runtime helpers for escaping text, constructing attributes, and assembling slots.
public enum ESW {
    /// Converts a value to HTML body text, escaping `&`, `<`, `>`, `"`, and `'`.
    ///
    /// Nested optionals are unwrapped; `nil` renders as an empty string.
    /// ``ESWValue/safe(_:)`` is emitted unchanged. Other values use their string
    /// description, with booleans rendered as `true` or `false`.
    ///
    /// This is HTML escaping, not HTML sanitization or JavaScript/CSS encoding.
    /// Dynamic attributes use ``attribute(_:_:)-(String,Any?)`` so body trust cannot bypass
    /// attribute escaping.
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
        return escaped(string)
    }

    /// ``escape(_:)`` for text that is already a `String`, without boxing it.
    static func escaped(_ string: String) -> String {
        var result = ""
        appendEscaped(string, to: &result)
        return result
    }

    /// Escapes text directly into `output`, copying it unchanged when no delimiter occurs.
    static func appendEscaped(_ string: String, to output: inout String) {
        // Match HTML delimiters as scalars, not extended grapheme clusters:
        // a quote followed by a combining mark must still be escaped.
        guard string.utf8.contains(where: { $0 == 34 || $0 == 38 || $0 == 39 || $0 == 60 || $0 == 62 }) else {
            output += string
            return
        }
        output.reserveCapacity(output.utf8.count + string.utf8.count + 16)
        for c in string.unicodeScalars {
            switch c {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&#39;"
            default: output.unicodeScalars.append(c)
            }
        }
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
