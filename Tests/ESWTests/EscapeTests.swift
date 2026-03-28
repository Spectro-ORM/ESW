import Testing
@testable import ESW

@Suite("ESW.escape")
struct EscapeTests {
    @Test func nilReturnsEmpty() {
        #expect(ESW.escape(nil) == "")
    }

    @Test func plainString() {
        #expect(ESW.escape("hello") == "hello")
    }

    @Test func escapesAmpersand() {
        #expect(ESW.escape("a&b") == "a&amp;b")
    }

    @Test func escapesLessThan() {
        #expect(ESW.escape("<div>") == "&lt;div&gt;")
    }

    @Test func escapesGreaterThan() {
        #expect(ESW.escape("1 > 0") == "1 &gt; 0")
    }

    @Test func escapesDoubleQuote() {
        #expect(ESW.escape("say \"hi\"") == "say &quot;hi&quot;")
    }

    @Test func escapesSingleQuote() {
        #expect(ESW.escape("it's") == "it&#39;s")
    }

    @Test func escapesAllSpecialChars() {
        #expect(ESW.escape("<a href=\"x\">&'") == "&lt;a href=&quot;x&quot;&gt;&amp;&#39;")
    }

    @Test func intPassesThrough() {
        #expect(ESW.escape(42) == "42")
    }

    @Test func negativeInt() {
        #expect(ESW.escape(-7) == "-7")
    }

    @Test func doublePassesThrough() {
        #expect(ESW.escape(3.14) == "3.14")
    }

    @Test func boolTrue() {
        #expect(ESW.escape(true) == "true")
    }

    @Test func boolFalse() {
        #expect(ESW.escape(false) == "false")
    }

    @Test func eswValueSafePassesThrough() {
        let val = ESWValue.safe("<b>bold</b>")
        #expect(ESW.escape(val) == "<b>bold</b>")
    }

    @Test func eswValueUnsafeIsEscaped() {
        let val = ESWValue.unsafe("<script>alert('xss')</script>")
        #expect(ESW.escape(val) == "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
    }

    @Test func fallbackUsesStringDescribing() {
        struct Custom: CustomStringConvertible {
            var description: String { "custom<value>" }
        }
        #expect(ESW.escape(Custom()) == "custom&lt;value&gt;")
    }

    // MARK: - render() helper

    @Test func renderWrapsAsSafe() {
        let html = "<p>Hello</p>"
        let wrapped = render(html)
        #expect(ESW.escape(wrapped) == "<p>Hello</p>")
    }

    @Test func renderPreventsDoubleEscaping() {
        let partial = "<b>Tom &amp; Jerry</b>"
        #expect(ESW.escape(render(partial)) == partial)
    }
}
