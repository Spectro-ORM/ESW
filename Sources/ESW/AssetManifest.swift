import Foundation

/// An immutable mapping from logical asset names to fingerprinted paths.
///
/// This type reads a mapping produced by your asset pipeline; it does not build,
/// hash, copy, or serve assets. Missing keys fall back to their original names.
public final class AssetManifest: Sendable {
    private let entries: [String: String]

    /// Loads a JSON object whose keys and values are strings.
    /// - Parameter jsonPath: A filesystem path, relative to the process working
    ///   directory when not absolute.
    /// - Throws: A file-reading or JSON-decoding error.
    public init(jsonPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        self.entries = try JSONDecoder().decode([String: String].self, from: data)
    }

    /// Creates a manifest from an in-memory mapping.
    public init(entries: [String: String]) {
        self.entries = entries
    }

    /// Returns the mapped path, or `name` when no mapping exists.
    public func path(for name: String) -> String {
        entries[name] ?? name
    }
}
