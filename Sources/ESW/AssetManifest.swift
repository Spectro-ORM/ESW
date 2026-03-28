import Foundation

public final class AssetManifest: Sendable {
    private let entries: [String: String]

    public init(jsonPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        self.entries = try JSONDecoder().decode([String: String].self, from: data)
    }

    public init(entries: [String: String]) {
        self.entries = entries
    }

    public func path(for name: String) -> String {
        entries[name] ?? name
    }
}
