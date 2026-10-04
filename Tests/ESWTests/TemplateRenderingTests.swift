import Testing
import ESW

private struct Card: ESWComponent {
    static func render(header: String = "", content: String = "") -> String {
        "<section>\(header)\(content)</section>"
    }
}

private struct Badge: ESWComponent {
    static func render(label: String, `class`: String = "") -> String {
        "<b\(ESW.attribute("class", `class`))>\(ESW.escape(label))</b>"
    }
}

private struct Button: ESWComponent {
    static func render(disabled: Bool, label: String) -> String {
        "<button\(ESW.attribute("disabled", disabled))>\(ESW.escape(label))</button>"
    }
}

@Suite("Compiled template rendering")
struct TemplateRenderingTests {
    @Test func inlineLiteralDecoding() {
        #expect(#esw("<p>\"hi\"\n\tthere</p>") == "<p>\"hi\"\n\tthere</p>")
        #expect(#esw(#"<p>\n</p>"#) == #"<p>\n</p>"#)
        #expect(#esw("<p>\u{1F30D}</p>") == "<p>🌍</p>")
    }

    @Test func literalCannotBecomeSwiftInterpolation() {
        #expect(#esw(##"<p>\#(42)</p>"##) == ##"<p>\#(42)</p>"##)
        #expect(#esw(###"<p>\##(42)</p>"###) == ###"<p>\##(42)</p>"###)
    }

    @Test func swiftDelimitersInsideStrings() {
        #expect(#esw(#"<%= "%>" %>"#) == "%&gt;")
        #expect(#esw(#"<.badge label={"}"} />"#) == "<b class=\"\">}</b>")
    }

    @Test func siblingComponentsAndTrailingText() {
        #expect(#esw("<.card>A</.card><.card>B</.card>after") == "<section>A</section><section>B</section>after")
    }

    @Test func nestedSlotOwnership() {
        let html = #esw("<.card><:header>Outer</:header><.card><:header>Inner</:header>Body</.card>Tail</.card>After")
        #expect(html == "<section>Outer<section>InnerBody</section>Tail</section>After")
    }

    @Test func nestedOptionalEscaping() {
        let absent: String? = nil
        let present: String?? = .some(.some("<b>"))
        #expect(#esw("<%= absent %>|<%= present %>") == "|&lt;b&gt;")
    }

    @Test func htmlAttributesAndBody() {
        let name = "\"<&"
        let disabled = false
        let title: String? = nil
        #expect(#heex("<button title={title} disabled={disabled}>{name}</button>") == "<button>&quot;&lt;&amp;</button>")
        #expect(#heex("<input disabled={true} />") == "<input disabled />")
    }

    @Test func bareComponentFlagBeforeOtherAttributes() {
        #expect(#esw(#"<.button disabled label="Save" />"#) == "<button disabled>Save</button>")
        #expect(#heex(#"<.button disabled :if={true} label="Save" />"#) == "<button disabled>Save</button>")
    }

    @Test func htmlTagNamesPreserveSourceCase() {
        #expect(#heex("<svg><linearGradient></linearGradient></svg>") == "<svg><linearGradient></linearGradient></svg>")
        #expect(#heex("<DIV>Text</DIV>") == "<DIV>Text</DIV>")
    }

    @Test func classListsAndAttributeMaps() {
        let active = true
        let attrs: [String: Any?] = ["title": "\"<", "hidden": false, "aria-expanded": false]
        let html = #heex(#"<div class={["button", active ? "active" : nil]} {attrs}></div>"#)
        #expect(html == "<div class=\"button active\" aria-expanded=\"false\" title=\"&quot;&lt;\"></div>")
    }

    @Test func directivesUseSwiftScope() {
        let items = [0, 1, 2]
        let html = #heex("<ul><li :if={item > 0} :for={item in items}>{item}</li></ul>")
        #expect(html == "<ul><li>1</li><li>2</li></ul>")
        let components = #heex(#"<.badge :for={item in items} :if={item > 1} label={String(item)} class="count" />"#)
        #expect(components == "<b class=\"count\">2</b>")
        #expect(#heex("<.card :if={false}>hidden</.card>tail") == "tail")
    }

    @Test func htmlCommentsAndRawTextStayLiteral() {
        #expect(#heex("<!-- <.missing> {ignored} --><script>if (x) { y = '<div>'; }</script>") == "<!-- <.missing> {ignored} --><script>if (x) { y = '<div>'; }</script>")
        #expect(#heex(#"<p>\{literal\}</p>"#) == "<p>{literal}</p>")
    }

    @Test func trustedHTMLDoesNotBypassAttributeEscaping() {
        let value = render("\" onmouseover=\"bad")
        #expect(#heex("<p title={value}>{value}</p>") == "<p title=\"&quot; onmouseover=&quot;bad\">\" onmouseover=\"bad</p>")
        #expect(ESW.attributes(["bad\" name": "x", "data-ok": "yes"]) == " data-ok=\"yes\"")
    }
}
