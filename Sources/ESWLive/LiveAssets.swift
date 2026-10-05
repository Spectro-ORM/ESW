import Foundation

/// Access to the browser modules packaged with the live runtime.
public enum LiveAssets {
    /// Whitelisted, locally bundled assets; no browser CDN dependency.
    /// - Parameter name: `esw-live.js`, `live-render.js` or `idiomorph.js`.
    /// - Returns: JavaScript source, or nil for an unknown name or unreadable resource.
    /// Serve the source as a JavaScript module with the appropriate content type.
    public static func javascript(named name: String) -> String? {
        guard ["esw-live.js", "live-render.js", "idiomorph.js"].contains(name),
              let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
