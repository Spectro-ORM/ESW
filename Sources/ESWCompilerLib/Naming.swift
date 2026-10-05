/// Shared renderer naming rules for file compilation and collision checks.
public enum Naming {
    /// Names are relative to the template root: users/index.heex → renderUsersIndex.
    /// Flat names retain their original spelling and partial convention.
    public static func functionName(from filename: String) -> String {
        let components = filename.split(separator: "/").map { component in
            let stem = component.split(separator: ".", maxSplits: 1).first ?? component
            return stem.split(whereSeparator: { $0 == "_" || $0 == "-" }).enumerated().map { index, word in
                let text = index == 0 ? word.lowercased() : String(word)
                return text.prefix(1).uppercased() + text.dropFirst()
            }.joined()
        }
        return "render" + components.joined() + (filename.hasSuffix(".live.heex") ? "Live" : "")
    }

    /// Returns the compatibility alias used for partial renderers.
    /// Its name includes `Buffer`, but ordinary partials still return `String`.
    public static func bufferFunctionName(from filename: String) -> String {
        "_" + functionName(from: filename) + "Buffer"
    }

    /// Reports whether the final path component begins with an underscore.
    public static func isPartial(_ filename: String) -> Bool {
        filename.split(separator: "/").last?.hasPrefix("_") == true
    }
}
