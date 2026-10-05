import Testing
@testable import ESWCompilerLib

@Suite("HTML compiler diagnostics")
struct HTMLCompilerTests {
    @Test func rawTextRetainsEExEvaluation() throws {
        let output = try compileExpression(source: "<script>let x = {literal}; <%= value %></script><!-- <%= note %> -->", syntax: .heex)
        #expect(output.contains("appendEscaped(value)"))
        #expect(output.contains("appendEscaped(note)"))
    }

    @Test func noCurlyInterpolationIsInheritedAndRemoved() throws {
        let output = try compileExpression(source: "<div phx-no-curly-interpolation><p title={title}>{client}</p><%= value %></div>", syntax: .heex)
        #expect(!output.contains("phx-no-curly-interpolation"))
        #expect(!output.contains("appendEscaped(client)"))
        #expect(output.contains("appendEscaped(value)"))
        #expect(output.contains("ESW.attribute("))
    }

    @Test func qualifiedComponentsCallSwiftFunctions() throws {
        let output = try compileExpression(source: #"<UI.card title="Title"><:header>Header</:header>Body</UI.card>"#, syntax: .heex)
        #expect(output.contains("UI.card("))
    }

    @Test func deferredRepeatedSlotsCompile() throws {
        let source = #"<.table rows={rows}><:column label="Name" :let={row}>{row.name}</:column><:column :for={label in labels} :if={!label.isEmpty} label={label} :let={row}>{row.id}</:column></.table>"#
        let output = try compile(source: source, filename: "page.heex", sourceFile: "page.heex")
        #expect(output.contains("ESW.slots"))
    }

    @Test(arguments: [
        "<div><span></div>", "<p>", "</p>", "<div id='a' id='b'></div>",
        "<p title={}></p>", "<p title='oops></p>", "<p title=<%= name %>></p>",
        "<p :if='yes'></p>", "<div :unknown={true}></div>", "<!-- unterminated",
        "<p :key={id}></p>", "<p :for={item in items} :key='id'></p>",
        "<p :for={item in items} :key={}></p>", "<p :for={item in items} :key={item} :key={item}></p>",
        "<.card :key={id} />", "<.card :for={item in items} :key='id' />",
        "<.card><:header :for={item in items} :key={item}>Title</:header></.card>",
        "<.card><p></.card></p>", "<.card><:header><b></:header></b></.card>",
        "<p title='a'title='b'></p>",
        "<.card :let={row} />", "<.card><:header :let={row} /></.card>",
        "<.card><div><:header>Bad placement</:header></div></.card>",
        "<.card header='duplicate'><:header>Header</:header></.card>",
        "<.card content='duplicate'>Body</.card>",
        "<.card :let={row}><:header>No default content</:header></.card>",
        "<.card :let={row in rows}>Body</.card>",
        "<.card phx-no-curly-interpolation={true}>Body</.card>",
        "<.card><:header phx-no-curly-interpolation='true'>Body</:header></.card>",
    ])
    func rejectsMalformedHTML(_ source: String) {
        #expect(throws: (any Error).self) {
            try compile(source: source, filename: "page.heex", sourceFile: "page.heex")
        }
    }

    @Test func diagnosticIncludesOpeningAndClosingLocations() {
        do {
            _ = try compile(source: "<div>\n<span>\n</div>", filename: "page.heex", sourceFile: "Views/page.heex")
            Issue.record("Expected mismatched tag error")
        } catch let error as ESWHTMLDiagnostic {
            #expect(error.metadata.line == 3)
            #expect(error.metadata.column == 1)
            #expect(error.description.contains("Views/page.heex:3:1: error:"))
            #expect(error.message.contains("line 2"))
            #expect(error.message.contains("</span>"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func eswStillAllowsFragmentsAndLiteralBraces() throws {
        _ = try compile(source: "<div>{literal}", filename: "page.esw", sourceFile: "page.esw")
    }

    @Test func fullParameterTypesSurviveCodeGeneration() throws {
        let source = "<%!\nvar map: [String: Int] = [:]\nvar transform: (String) -> String = { $0 }\n%><%= transform(String(map.count)) %>"
        let generated = try compile(source: source, filename: "types.esw", sourceFile: "types.esw")
        #expect(generated.contains("map: [String: Int] = [:]"))
        #expect(generated.contains("transform: (String) -> String = { $0 }"))
    }

    @Test(arguments: ["<. />", "<.1invalid />", "<.card value={} />", "<.card x='a' x='b' />", "<.card x='a'y='b' />"])
    func rejectsMalformedComponents(_ source: String) {
        #expect(throws: ESWTokenizerError.self) {
            try compile(source: source, filename: "page.esw", sourceFile: "page.esw")
        }
    }

    @Test func componentCloseThrowsPublicDiagnosticType() {
        #expect(throws: ESWComponentError.unmatchedComponentClose(file: "page.esw", line: 1, column: 14)) {
            try compile(source: "<.a><.b></.b></.wrong>", filename: "page.esw", sourceFile: "page.esw")
        }
    }

    @Test func bracesAndTagDelimitersInSwiftComments() throws {
        let source = #"<.badge label={ /* } /* nested */ */ "}" } /><%= /* %> */ "%>" %>"#
        _ = try compile(source: source, filename: "page.esw", sourceFile: "page.esw")
    }

    @Test func escapedPathInSourceLocation() throws {
        let generated = try compile(source: "<%= name %>", filename: "page.esw", sourceFile: "a\"b\\c.esw")
        #expect(generated.contains(#"file: "a\"b\\c.esw""#))
    }
}
