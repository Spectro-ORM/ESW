public enum Naming {

    /// Converts an `.esw` filename to a Swift function name per spec §8.4.
    ///
    /// - Strips the `.esw` extension
    /// - Strips leading underscores (partial convention)
    /// - Converts `snake_case` to `camelCase`
    /// - Prefixes with `render`
    ///
    /// Examples:
    /// - `user_profile.esw` → `renderUserProfile`
    /// - `layout.esw` → `renderLayout`
    /// - `_user_card.esw` → `renderUserCard`
    /// - `index.esw` → `renderIndex`
    public static func functionName(from filename: String) -> String {
        var stem = filename
        if stem.hasSuffix(".esw") {
            stem = String(stem.dropLast(4))
        }

        // Strip leading underscores
        while stem.hasPrefix("_") {
            stem = String(stem.dropFirst())
        }

        let camelCased = snakeToCamelCase(stem)
        return "render" + capitalizeFirst(camelCased)
    }

    /// Converts `snake_case` to `camelCase`.
    private static func snakeToCamelCase(_ input: String) -> String {
        let parts = input.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return input }

        var result = String(first).lowercased()
        for part in parts.dropFirst() {
            result += capitalizeFirst(String(part))
        }
        return result
    }

    /// Capitalizes the first character of a string.
    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// Converts a filename to the buffer function name (for partials).
    /// e.g. `_user_card.esw` → `_renderUserCardBuffer`
    public static func bufferFunctionName(from filename: String) -> String {
        "_" + functionName(from: filename) + "Buffer"
    }

    /// Checks if a filename represents a partial (starts with `_`).
    public static func isPartial(_ filename: String) -> Bool {
        var stem = filename
        if stem.hasSuffix(".esw") {
            stem = String(stem.dropLast(4))
        }
        return stem.hasPrefix("_")
    }
}
