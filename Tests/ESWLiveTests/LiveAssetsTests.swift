import ESWLive
import Testing

@Suite("Live browser assets")
struct LiveAssetsTests {
    @Test func entryPointAndEveryImportedModuleAreBundled() throws {
        let entry = try #require(LiveAssets.javascript(named: "esw-live.js"))
        #expect(entry.contains("./live-render.js"))
        #expect(entry.contains("./idiomorph.js"))
        #expect(LiveAssets.javascript(named: "live-render.js")?.contains("export function applyRenderPatch") == true)
        #expect(LiveAssets.javascript(named: "idiomorph.js") != nil)
        #expect(LiveAssets.javascript(named: "../Interactive.swift") == nil)
    }
}
