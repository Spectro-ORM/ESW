import Testing
@testable import ESWCompilerLib

@Suite("Scoped styles")
struct ScopedStyleTests {
    @Test func batchScopesTopLevelElementsAndCollectsCSS() throws {
        let card = TemplateSource(name: "ui/card.hesw", source: """
            <style :scoped>
              .title { color: red; }
            </style>
            <article><h1 class="title">Hi</h1></article>
            <.badge><span>slot</span></.badge>
            <hr />
            """, sourceFile: "Views/ui/card.hesw")
        let output = try compileTemplates([card], emitSourceLocations: false)
        let id = Naming.scopeID(for: "ui/card.hesw")
        #expect(id.hasPrefix("card-"))
        #expect(output.contains("<article data-esw=\"\(id)\"><h1 class=\"title\">"))
        #expect(output.contains("<span data-esw=\"\(id)\">slot"))
        #expect(output.contains("<hr data-esw=\"\(id)\" />"))
        let renderer = output[..<(output.firstRange(of: "/// CSS from this target")?.lowerBound ?? output.endIndex)]
        #expect(!renderer.contains("<style"))
        #expect(output.contains("/* ui/card.hesw */\n@scope ([data-esw=\"\(id)\"]) to ([data-esw]) {"))
        #expect(output.contains(".title { color: red; }"))
    }

    @Test func templatesWithoutScopedStylesAreUnchanged() throws {
        let page = TemplateSource(name: "page.hesw", source: "<style>p { margin: 0; }</style><p>Hi</p>", sourceFile: "page.hesw")
        let output = try compileTemplates([page])
        #expect(output.contains("<style>p { margin: 0; }</style><p>Hi</p>"))
        #expect(!output.contains("data-esw"))
        #expect(output.contains("public enum ESWStyles {\n    public static let css = #\"\"#\n}"))
    }

    @Test func scopedStylesNeedBatchCompilation() {
        let source = "<style :scoped>p {}</style><p>x</p>"
        #expect(throws: ESWHTMLDiagnostic.self) { try compileExpression(source: source, syntax: .hesw) }
        #expect(throws: ESWTemplateError.self) { try compile(source: source, filename: "a.hesw", sourceFile: "a.hesw") }
    }

    @Test(arguments: [
        ("<div :scoped>x</div>", ":scoped applies only to <style>"),
        ("<style :scoped media=\"print\">p {}</style><p>x</p>", "takes no other attributes"),
        ("<div><style :scoped>p {}</style></div>", "must be a top-level element"),
        ("<style :scoped>p { color: <%= c %> }</style><p>x</p>", "must contain static CSS"),
        ("<style :scoped>p {}</style>text only", "needs a top-level HTML element"),
    ])
    func invalidScopedStyles(source: String, message: String) {
        do {
            _ = try compileTemplates([TemplateSource(name: "bad.hesw", source: source, sourceFile: "bad.hesw")])
            Issue.record("expected an error for \(source)")
        } catch {
            #expect(String(describing: error).contains(message))
        }
    }
}
