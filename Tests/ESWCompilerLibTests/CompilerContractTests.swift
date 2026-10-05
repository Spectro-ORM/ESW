import Testing
@testable import ESWCompilerLib

@Suite("Peregrine compiler contracts")
struct CompilerContractTests {
    @Test func liveFilesGenerateStructuredRenderFunctions() throws {
        let output = try compile(source: "<%! var count: Int %><p>{count}</p>", filename: "counter.live.heex", sourceFile: "counter.live.heex")
        #expect(output.contains("func renderCounterLive("))
        #expect(output.contains(") -> ESWLiveRender"))
        #expect(output.contains("ESWLiveBuffer()"))
    }

    @Test func batchIsDeterministicAndRejectsNormalizedCollisions() throws {
        let users = TemplateSource(name: "users/index.heex", source: "<p>Users</p>", sourceFile: "Views/users/index.heex")
        let posts = TemplateSource(name: "posts/index.esw", source: "Posts", sourceFile: "Views/posts/index.esw")
        #expect(try compileTemplates([users, posts]) == compileTemplates([posts, users]))
        #expect(throws: ESWTemplateError.self) {
            try compileTemplates([
                TemplateSource(name: "user_card.esw", source: "", sourceFile: "user_card.esw"),
                TemplateSource(name: "user-card.heex", source: "", sourceFile: "user-card.heex"),
            ])
        }
    }

    @Test func resourcePathsHaveDistinctNames() {
        #expect(Naming.functionName(from: "users/index.heex") == "renderUsersIndex")
        #expect(Naming.functionName(from: "posts/index.esw") == "renderPostsIndex")
        #expect(Naming.bufferFunctionName(from: "users/_card.heex") == "_renderUsersCardBuffer")
        #expect(Naming.isPartial("users/_card.heex"))
    }

    @Test func swiftDeclarationsAndExplicitImports() throws {
        let source = """
        <%!
        import Foundation
        let date: Date
        var labels: [String] = [
            "first",
            "second"
        ]
        var transform: (String) -> String = { value in
            value.uppercased()
        }
        %>
        <%= transform(labels[0]) %>
        """
        let output = try compile(source: source, filename: "page.esw", sourceFile: "page.esw")
        #expect(output.contains("import Foundation"))
        #expect(output.contains("date: Date"))
        #expect(output.contains("value.uppercased()"))
        #expect(output.contains("\"second\""))
    }

    @Test func userTypeDoesNotGuessAFrameworkImport() throws {
        let output = try compile(source: "<%! var connection: DatabaseConnection %>", filename: "page.esw", sourceFile: "page.esw")
        #expect(!output.contains("import Nexus"))
    }

    @Test func explicitImportsOverrideLegacyConnectionCompatibility() throws {
        let legacy = try compile(source: "<%! var conn: Connection %>", filename: "page.esw", sourceFile: "page.esw")
        #expect(legacy.contains("import Nexus"))
        let explicit = try compile(source: "<%!\nimport CustomHTTP\nvar conn: Connection\n%>", filename: "page.esw", sourceFile: "page.esw")
        #expect(explicit.contains("import CustomHTTP"))
        #expect(!explicit.contains("import Nexus"))
    }

    @Test func declarationErrorPointsAtItsSourceLine() {
        do {
            _ = try compile(source: "<%!\n// comment\nvar count: Int\nfunc invalid() {}\n%>", filename: "page.esw", sourceFile: "Views/page.esw")
            Issue.record("Expected a declaration diagnostic")
        } catch let ESWAssignsError.invalidDeclaration(file, line, _) {
            #expect(file == "Views/page.esw")
            #expect(line == 4)
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}
