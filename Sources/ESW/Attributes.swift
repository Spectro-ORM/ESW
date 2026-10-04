extension ESW {
    /// Renders a complete, quoted HTML attribute (including its leading space).
    /// Trusted HTML is still escaped here: text safety does not imply attribute safety.
    public static func attribute(_ name: String, _ value: Any?) -> String {
        guard validAttributeName(name), let value = unwrapped(value) else { return "" }
        if let flag = value as? Bool {
            if name.hasPrefix("aria-") || name.hasPrefix("data-") {
                return " \(name)=\"\(flag ? "true" : "false")\""
            }
            return flag ? " \(name)" : ""
        }
        let text: String
        if name == "class", let values = value as? [Any?] {
            text = classNames(values).joined(separator: " ")
        } else {
            text = attributeText(value)
        }
        return " \(name)=\"\(escape(text))\""
    }

    /// Attribute maps render in a stable order. Invalid names are omitted.
    public static func attributes(_ values: [String: Any?]) -> String {
        values.keys.sorted().map { attribute($0, values[$0] ?? nil) }.joined()
    }

    private static func attributeText(_ value: Any) -> String {
        if let html = value as? ESWValue {
            switch html {
            case .safe(let text), .unsafe(let text): return text
            }
        }
        return String(describing: value)
    }

    private static func classNames(_ values: [Any?]) -> [String] {
        values.flatMap { value -> [String] in
            guard let value = unwrapped(value), !(value is Bool) else { return [] }
            if let nested = value as? [Any?] { return classNames(nested) }
            let text = attributeText(value)
            return text.isEmpty ? [] : [text]
        }
    }

    private static func validAttributeName(_ name: String) -> Bool {
        guard let first = name.utf8.first,
              (65...90).contains(first) || (97...122).contains(first) || first == 95 else { return false }
        return name.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 95 || $0 == 58 || $0 == 46
        }
    }
}
