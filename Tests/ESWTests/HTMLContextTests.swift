import Testing
import ESW

private enum UI {
    static func card(title: String, header: String, content: String) -> String {
        "<article><h1>\(ESW.escape(title))</h1>\(header)\(content)</article>"
    }
    static func badge(label: String) -> String { "<b>\(ESW.escape(label))</b>" }
}

@Suite("HTML interpolation contexts")
struct HTMLContextTests {
    @Test func typedFastPathsMatchGenericEscaping() {
        for text in ["plain", "", "\"\u{301}<A & 'b'>"] {
            var typed = ESWBuffer(), generic = ESWBuffer()
            typed.appendEscaped(text)
            generic.appendEscaped(text as Any)
            #expect(typed.finalize() == generic.finalize())
            #expect(ESW.attribute("title", text) == ESW.attribute("title", text as Any?))
            var live = ESWLiveBuffer(), genericLive = ESWLiveBuffer()
            live.appendEscaped(text)
            genericLive.appendEscaped(text as Any)
            #expect(live.finalize() == genericLive.finalize())
        }
        var typed = ESWBuffer(), generic = ESWBuffer()
        typed.appendEscaped(nil as String?)
        typed.appendEscaped(-42)
        generic.appendEscaped(nil as String? as Any)
        generic.appendEscaped(-42 as Any)
        #expect(typed.finalize() == generic.finalize())
        #expect(ESW.attribute("bad name", "x") == "")
    }

    @Test func rawTextAndCommentsEvaluateEEx() {
        let value = 42
        let note = "<note>"
        #expect(#hesw("<script>if (x) { y = <%= value %>; }</script><style>p { z-index: <%= value %>; }</style><!-- {literal} <%= note %> -->") == "<script>if (x) { y = 42; }</script><style>p { z-index: 42; }</style><!-- {literal} &lt;note&gt; -->")
    }

    @Test func rawTextAndCommentsHonorEscapedEExDelimiters() {
        #expect(#hesw("<script><%%= literal %%></script><style><%%= literal %%></style><!-- <%%= literal %%> -->") == "<script><%= literal %></script><style><%= literal %></style><!-- <%= literal %> -->")
    }

    @Test func noCurlyInterpolationHasSubtreeScope() {
        let value = "<value>"
        let title = "\"quote"
        #expect(#hesw("<div phx-no-curly-interpolation><p title={title}>{client}</p><%= value %></div><p>{value}</p>") == "<div><p title=\"&quot;quote\">{client}</p>&lt;value&gt;</div><p>&lt;value&gt;</p>")
    }

    @Test func noCurlyInterpolationWorksOnComponentsAndNamedSlots() {
        let value = "<value>"
        #expect(#hesw(#"<UI.card title={value} phx-no-curly-interpolation><:header>{header}</:header><p>{client}</p><%= value %></UI.card><p>{value}</p>"#) == "<article><h1>&lt;value&gt;</h1>{header}<p>{client}</p>&lt;value&gt;</article><p>&lt;value&gt;</p>")
        #expect(#hesw(#"<UI.card title="Title"><:header phx-no-curly-interpolation>{header}<%= value %></:header><p>{value}</p></UI.card>"#) == "<article><h1>Title</h1>{header}&lt;value&gt;<p>&lt;value&gt;</p></article>")
    }

    @Test func qualifiedFunctionsSupportSlotsAndDirectives() {
        let labels = ["<Ada>", ""]
        #expect(#hesw(#"<UI.card title="Title"><:header><b>Header</b></:header><UI.badge :for={label in labels} :if={!label.isEmpty} label={label} /></UI.card>"#) == "<article><h1>Title</h1><b>Header</b><b>&lt;Ada&gt;</b></article>")
    }
}
