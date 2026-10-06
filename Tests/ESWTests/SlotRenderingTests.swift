import Testing
import ESW

private struct SlotRow { let name: String }
private struct ColumnAttributes { let label: String }

private struct SlotTable: ESWComponent {
    static func render(rows: [SlotRow], column: [ESWSlot<ColumnAttributes, SlotRow>]) -> String {
        let header = column.map { "<th>\(ESW.escape($0.attributes.label))</th>" }.joined()
        let body = rows.map { row in
            "<tr>" + column.map { "<td>\($0.render(row))</td>" }.joined() + "</tr>"
        }.joined()
        return "<table><thead>\(header)</thead><tbody>\(body)</tbody></table>"
    }
}

private struct SlotRepeater: ESWComponent {
    static func render(rows: [SlotRow], header: String = "", content: (SlotRow) -> String) -> String {
        header + rows.map(content).joined()
    }
}

private struct SlotPair: ESWComponent {
    static func render(entry: [ESWSlot<ESWEmptySlotAttributes, (String, Int)>]) -> String {
        ESW.escape(renderSlot(entry, ("<key>", 2)))
    }
}

private struct SlotDiscarder: ESWComponent {
    static func render(entry: [ESWSlot<ColumnAttributes, Void>]) -> String { "unused" }
}

private struct FormContext { let fieldName: String; let value: String }
private struct Form: ESWComponent {
    static func render(value: String, content: (FormContext) -> String) -> String {
        "<form>" + content(FormContext(fieldName: "name", value: value)) + "</form>"
    }
}

private struct SlotNotices: ESWComponent {
    static func render(notice: [ESWSlot<ESWEmptySlotAttributes, Void>] = []) -> String {
        #hesw("<aside>{renderSlot(notice)}</aside>")
    }
}

@Suite("Typed deferred slots")
struct SlotRenderingTests {
    @Test func generatedLocalsDoNotShadowCallerValuesOrSlotBindings() {
        let _buf = "<outer>"
        let _buf1 = "<next>"
        #expect(#hesw("<p>{_buf}{_buf1}</p>") == "<p>&lt;outer&gt;&lt;next&gt;</p>")
        let rows = [SlotRow(name: "<Ada>")]
        #expect(#hesw("<.slot-repeater rows={rows} :let={_buf}><b>{_buf.name}</b></.slot-repeater>") == "<b>&lt;Ada&gt;</b>")
        #expect(#hesw(#"<.slot-table rows={rows}><:column label="Name" :let={_buf}>{_buf.name}</:column></.slot-table>"#) == "<table><thead><th>Name</th></thead><tbody><tr><td>&lt;Ada&gt;</td></tr></tbody></table>")
        #expect(#hesw("<.slot-pair><:entry :let={(__esw_slot_value, _buf)}>{__esw_slot_value}:{_buf}</:entry></.slot-pair>") == "&lt;key&gt;:2")
    }

    @Test func typedFormContextEscapesInputValues() {
        let name = "\"\u{301}<Ada>"
        #expect(#hesw("<.form value={name} :let={form}><input name={form.fieldName} value={form.value} /></.form>") == "<form><input name=\"name\" value=\"&quot;\u{301}&lt;Ada&gt;\" /></form>")
    }

    @Test func repeatedSimpleEntriesAndOptionalSlot() {
        #expect(#hesw("<.slot-notices><:notice><b>A</b></:notice><:notice>B</:notice></.slot-notices>") == "<aside><b>A</b>B</aside>")
        #expect(#hesw("<.slot-notices />") == "<aside></aside>")
    }

    @Test func repeatedColumnsBindRowsAndPreserveEntryOrder() {
        let rows = [SlotRow(name: "<Ada>")]
        let html = #hesw(#"<.slot-table rows={rows}><:column label="First" :let={row}><b>{row.name}</b></:column><:column label="Second" :let={row}>{row.name}</:column></.slot-table>"#)
        #expect(html == "<table><thead><th>First</th><th>Second</th></thead><tbody><tr><td><b>&lt;Ada&gt;</b></td><td>&lt;Ada&gt;</td></tr></tbody></table>")
    }

    @Test func slotDirectivesBuildEntriesInCallerScope() {
        let rows = [SlotRow(name: "Ada")]
        let labels = ["<First>", "", "Second"]
        let html = #hesw(#"<.slot-table rows={rows}><:column :if={!label.isEmpty} :for={label in labels} label={label} :let={row}>{label}:{row.name}</:column></.slot-table>"#)
        #expect(html == "<table><thead><th>&lt;First&gt;</th><th>Second</th></thead><tbody><tr><td>&lt;First&gt;:Ada</td><td>Second:Ada</td></tr></tbody></table>")
        #expect(#hesw(#"<.slot-table rows={rows}><:column :if={false} label="Hidden" :let={row}>{row.name}</:column></.slot-table>"#) == "<table><thead></thead><tbody><tr></tr></tbody></table>")
    }

    @Test func defaultBindingDoesNotLeakIntoNamedSlots() {
        let rows = [SlotRow(name: "<Ada>"), SlotRow(name: "Grace")]
        let row = "Heading"
        let html = #hesw("<.slot-repeater rows={rows} :let={row}><:header><h1>{row}</h1></:header><p>{row.name}</p></.slot-repeater>")
        #expect(html == "<h1>Heading</h1><p>&lt;Ada&gt;</p><p>Grace</p>")
    }

    @Test func tupleBindingsAndTrustedSlotOutput() {
        #expect(#hesw("<.slot-pair><:entry :let={(key, count)}><b>{key}:{count}</b></:entry></.slot-pair>") == "<b>&lt;key&gt;:2</b>")
    }

    @Test func slotBodiesAreLazyButAttributesAreEager() {
        var bodyCalls = 0
        var attributeCalls = 0
        func label() -> String { attributeCalls += 1; return "Label" }
        let html = #hesw("<.slot-discarder><:entry label={label()}><% bodyCalls += 1 %>unused</:entry></.slot-discarder>")
        #expect(html == "unused")
        #expect(attributeCalls == 1)
        #expect(bodyCalls == 0)
    }

    @Test func formattingAroundNamedSlotsDoesNotCreateDefaultContent() {
        let rows: [SlotRow] = []
        #expect(#hesw("""
        <.slot-table rows={rows}>
          <:column label="Name" :let={row}>{row.name}</:column>
        </.slot-table>
        """) == "<table><thead><th>Name</th></thead><tbody></tbody></table>")
    }
}
