import Testing
import Foundation
@testable import ESW

@Suite("AssetManifest")
struct AssetManifestTests {

    @Test func lookupExistingEntry() throws {
        let manifest = AssetManifest(entries: [
            "app.css": "app-abc123.css",
            "app.js": "app-def456.js",
        ])
        #expect(manifest.path(for: "app.css") == "app-abc123.css")
        #expect(manifest.path(for: "app.js") == "app-def456.js")
    }

    @Test func missingEntryFallsBackToName() throws {
        let manifest = AssetManifest(entries: ["app.css": "app-abc123.css"])
        #expect(manifest.path(for: "missing.js") == "missing.js")
    }

    @Test func emptyManifest() throws {
        let manifest = AssetManifest(entries: [:])
        #expect(manifest.path(for: "app.css") == "app.css")
    }

    @Test func loadFromJSON() throws {
        let json = #"{"app.css":"app-abc123.css","app.js":"app-def456.js"}"#
        let tmpDir = FileManager.default.temporaryDirectory
        let path = tmpDir.appendingPathComponent("test_manifest_\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        let manifest = try AssetManifest(jsonPath: path.path)
        #expect(manifest.path(for: "app.css") == "app-abc123.css")
        #expect(manifest.path(for: "app.js") == "app-def456.js")
    }

    @Test func loadFromInvalidPathThrows() throws {
        #expect(throws: (any Error).self) {
            try AssetManifest(jsonPath: "/nonexistent/manifest.json")
        }
    }
}
