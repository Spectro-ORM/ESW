import Testing
@testable import ESWCompilerLib

@Suite("Typed template views")
struct TemplateViewTests {
    @Test func discoversExplicitTemplatesInOrdinarySwiftFiles() throws {
        let views = try TemplateView.discover(source: #"""
        import Foundation
        struct Helper {}
        @ESWTemplate("auth/register.esw")
        struct RegisterView { var email = "" }
        @ESW.ESWTemplate("card.hesw")
        public struct Card<Value> { let value: Value }
        """#, sourceFile: "Views.swift")
        #expect(views.map(\.typeName) == ["RegisterView", "Card"])
        #expect(views.map(\.templatePath) == ["auth/register.esw", "card.hesw"])
        #expect(views[0].imports == ["import Foundation"])
        #expect(views[1].accessModifier == "public ")
        #expect(try TemplateView.discover(source: "struct Helper {}", sourceFile: "Helper.swift").isEmpty)
    }

    @Test(arguments: [
        #"@ESWTemplate(path) struct A {}"#,
        #"@ESWTemplate("page.txt") struct A {}"#,
        #"@ESWTemplate("/page.esw") struct A {}"#,
        #"@ESWTemplate("page.esw") private struct A {}"#,
        #"@ESWTemplate("page.esw") class A {}"#,
        #"struct Outer { @ESWTemplate("page.esw") struct A {} }"#,
        "#if DEBUG\n@ESWTemplate(\"page.esw\") struct A {}\n#endif",
        #"@ESWTemplate("a.esw") @ESWTemplate("b.esw") struct A {}"#,
    ])
    func rejectsInvalidAssociations(source: String) {
        #expect(throws: ESWTemplateError.self) {
            try TemplateView.discover(source: source, sourceFile: "View.swift")
        }
    }

    @Test func compilesIntoTheCompanionType() throws {
        let view = try TemplateView(source: """
        import Foundation
        struct LoginView {
            let email: String
            var title = "Log in"
        }
        """, sourceFile: "Views/login.esw.swift")
        let output = try compile(source: "<h1><%= title %></h1><input value=\"<%= email %>\">",
                                 filename: "login.esw", sourceFile: "Views/login.esw", view: view)
        #expect(output.contains("import Foundation"))
        #expect(output.contains("extension LoginView {"))
        #expect(output.contains("func render() -> String"))
        #expect(!output.contains("func renderLogin("))
        #expect(!output.contains("let email:"))
        #expect(output.contains("#sourceLocation(file: \"Views/login.esw\", line: 1)"))
    }

    @Test func preservesConditionalImportsWithoutCopyingDeclarations() throws {
        let view = try TemplateView(source: """
        #if canImport(Foundation)
        import Foundation
        let helper = 1
        #elseif os(Linux)
        import Glibc
        #else
        #if DEBUG
        import Dispatch
        #endif
        #endif
        struct Card<Value> { let value: Value }
        """, sourceFile: "card.hesw.swift")
        #expect(view.typeName == "Card")
        #expect(view.imports == ["""
        #if canImport(Foundation)
        import Foundation
        #elseif os(Linux)
        import Glibc
        #else
        #if DEBUG
        import Dispatch
        #endif
        #endif
        """])
    }

    @Test(arguments: ["", "public", "package"])
    func visibilityFollowsTheView(access: String) throws {
        let view = try TemplateView(source: "\(access) struct Card {}", sourceFile: "card.esw.swift")
        let output = try compile(source: "", filename: "card.esw", sourceFile: "card.esw", view: view)
        let prefix = access.isEmpty ? "" : access + " "
        #expect(output.contains("    \(prefix)func render() -> String {"))
    }

    @Test(arguments: [
        "", "struct A {} struct B {}", "class View {}", "private struct View {}",
        "fileprivate struct View {}", "struct View {", "#if DEBUG\nstruct View {}\n#endif",
    ])
    func rejectsAmbiguousOrInaccessibleCompanions(source: String) {
        #expect(throws: ESWTemplateError.self) {
            try TemplateView(source: source, sourceFile: "login.esw.swift")
        }
    }

    @Test func rejectsParameterBlocksInTypedViews() throws {
        let view = try TemplateView(source: "struct Card {}", sourceFile: "card.esw.swift")
        #expect(throws: ESWTemplateError.self) {
            try compile(source: "<%! var title: String %><h1><%= title %></h1>",
                        filename: "card.esw", sourceFile: "card.esw", view: view)
        }
    }

    @Test func liveViewsKeepStructuredRenderingAndTypedPartialsOnlyGenerateMethods() throws {
        let view = try TemplateView(source: "struct Counter { let count: Int }", sourceFile: "_counter.live.hesw.swift")
        let output = try compile(source: "<output>{count}</output>", filename: "_counter.live.hesw",
                                 sourceFile: "_counter.live.hesw", view: view)
        #expect(output.contains("func render() -> ESWLiveRender"))
        #expect(output.contains("ESWLiveBuffer()"))
        #expect(!output.contains("_renderCounterLiveBuffer"))
    }

    @Test func batchChecksTheGeneratedSymbols() throws {
        let view = try TemplateView(source: "struct Card {}", sourceFile: "card.esw.swift")
        let typed = TemplateSource(name: "user_card.esw", source: "Typed", sourceFile: "user_card.esw", view: view)
        let legacy = TemplateSource(name: "user-card.hesw", source: "Legacy", sourceFile: "user-card.hesw")
        #expect(try compileTemplates([typed, legacy]).contains("extension Card"))
        let duplicate = TemplateSource(name: "other.esw", source: "", sourceFile: "other.esw", view: view)
        #expect(throws: ESWTemplateError.self) { try compileTemplates([typed, duplicate]) }
    }
}
