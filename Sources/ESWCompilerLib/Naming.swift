/// Shared renderer naming rules for file compilation and collision checks.
public enum Naming {
    /// Names are relative to the template root: users/index.hesw → renderUsersIndex.
    /// Flat names retain their original spelling and partial convention.
    public static func functionName(from filename: String) -> String {
        let components = filename.split(separator: "/").map { component in
            let stem = component.split(separator: ".", maxSplits: 1).first ?? component
            return stem.split(whereSeparator: { $0 == "_" || $0 == "-" }).enumerated().map { index, word in
                let text = index == 0 ? word.lowercased() : String(word)
                return text.prefix(1).uppercased() + text.dropFirst()
            }.joined()
        }
        return "render" + components.joined() + (TemplateSyntax.isLive(path: filename) ? "Live" : "")
    }

    /// Returns the compatibility alias used for partial renderers.
    /// Its name includes `Buffer`, but ordinary partials still return `String`.
    public static func bufferFunctionName(from filename: String) -> String {
        "_" + functionName(from: filename) + "Buffer"
    }

    /// The `data-esw` value for a template with `<style :scoped>`: its file stem
    /// plus a hash of the logical path, stable across machines and builds.
    public static func scopeID(for filename: String) -> String {
        let file = filename.split(separator: "/").last ?? Substring(filename)
        let stem = file.split(separator: ".", maxSplits: 1).first ?? file
        let slug = String(stem.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in filename.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return slug + "-" + String(hash, radix: 16)
    }

    /// Reports whether the final path component begins with an underscore.
    public static func isPartial(_ filename: String) -> Bool {
        filename.split(separator: "/").last?.hasPrefix("_") == true
    }
}
