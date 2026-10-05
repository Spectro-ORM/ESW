import ESW
import Foundation
import Testing

private struct LiveCard: ESWComponent {
    static func render(title: String, content: (String) -> String) -> String {
        "<article>" + content(title) + "</article>"
    }
}

private enum KeyedUI {
    static func label(value: Int) -> String { "<b>\(value)</b>" }
}

@Suite("Live render snapshots")
struct LiveRenderTests {
    @Test func keyedInsertionAndReorderingDoNotResendUnchangedRows() throws {
        func page(_ items: [Int]) -> ESWLiveRender {
            #live("<ul><li :for={item in items} :key={item}>{item}</li></ul>")
        }
        let before = page([1, 2])
        let inserted = page([3, 1, 2])
        let patch = before.diff(to: inserted)
        #expect(inserted.html == "<ul><li>3</li><li>1</li><li>2</li></ul>")
        #expect(patch.statics == nil)
        #expect(patch.dynamics.isEmpty)
        let rows = try #require(patch.keyed?["0"])
        #expect(rows.order == ["3", "1", "2"])
        #expect(Set(rows.entries.keys) == ["3"])
        let reordered = inserted.diff(to: page([2, 3, 1]))
        #expect(reordered.keyed?["0"]?.order == ["2", "3", "1"])
        #expect(reordered.keyed?["0"]?.entries.isEmpty == true)
        let deleted = inserted.diff(to: page([1]))
        #expect(deleted.keyed?["0"]?.order == ["1"])
        #expect(deleted.keyed?["0"]?.entries.isEmpty == true)
        let empty = before.diff(to: page([]))
        #expect(empty.statics == nil)
        #expect(empty.keyed?["0"]?.order == [])
        #expect(empty.keyed?["0"]?.entries.isEmpty == true)
        #expect(before.diff(to: before).keyed == nil)
        #expect(try JSONDecoder().decode(ESWLiveRender.self, from: JSONEncoder().encode(before)) == before)
        #expect(try JSONDecoder().decode(ESWLivePatch.self, from: JSONEncoder().encode(patch)) == patch)
    }

    @Test func keyedRowsDiffTheirOwnDynamicValues() throws {
        func page(_ items: [(id: Int, name: String)]) -> ESWLiveRender {
            #live("<ul><li :key={item.id} :if={!item.name.isEmpty} :for={item in items}>{item.name}</li></ul>")
        }
        let before = page([(1, "One"), (2, "Two"), (3, "")])
        let after = page([(1, "One"), (2, "<Changed>")])
        let patch = try #require(before.diff(to: after).keyed?["0"])
        #expect(patch.order == nil)
        #expect(Set(patch.entries.keys) == ["2"])
        #expect(patch.entries["2"]?.statics == nil)
        #expect(patch.entries["2"]?.dynamics == ["0": "&lt;Changed&gt;"])
        let items = [(id: 1, name: "One"), (id: 2, name: "<Changed>")]
        #expect(after.html == #heex("<ul><li :key={item.id} :if={!item.name.isEmpty} :for={item in items}>{item.name}</li></ul>"))
    }

    @Test func nestedKeyedListsKeepSeparateIdentityScopes() throws {
        func page(_ groups: [[Int]]) -> ESWLiveRender {
            #live("<section :for={(id, items) in groups.enumerated()} :key={id}><p :for={item in items} :key={item}>{item}</p></section>")
        }
        let before = page([[1, 2], [1, 2]])
        let after = page([[2, 1], [1, 3, 2]])
        let outer = try #require(before.diff(to: after).keyed?["0"])
        #expect(outer.order == nil)
        #expect(outer.entries["0"]?.keyed?["0"]?.order == ["2", "1"])
        #expect(outer.entries["0"]?.keyed?["0"]?.entries.isEmpty == true)
        #expect(Set(try #require(outer.entries["1"]?.keyed?["0"]).entries.keys) == ["3"])
        #expect(after.html == "<section><p>2</p><p>1</p></section><section><p>1</p><p>3</p><p>2</p></section>")
    }

    @Test func keyedComponentsRetainTypedSlots() throws {
        func page(_ names: [String]) -> ESWLiveRender {
            #live("<.live-card :for={name in names} :key={name} title={name} :let={label}><p>{label}</p></.live-card>")
        }
        let first = page(["One", "<Two>"])
        #expect(first.html == "<article><p>One</p></article><article><p>&lt;Two&gt;</p></article>")
        let patch = try #require(first.diff(to: page(["<Two>", "One"])).keyed?["0"])
        #expect(patch.order?.count == 2)
        #expect(patch.entries.isEmpty)
        let items = [1, 2]
        #expect(#live("<br :for={item in items} :key={item} />").html == "<br /><br />")
        let labels = #live("<KeyedUI.label :key={item} value={item} :for={item in items} />")
        #expect(labels.html == "<b>1</b><b>2</b>")
        #expect(labels.keyed["0"]?.order == ["1", "2"])
    }

    @Test func aRowShapeChangeReplacesOnlyThatRow() throws {
        func page(_ values: [String]) -> ESWLiveRender {
            #live("<li :for={(id, value) in values.enumerated()} :key={id}><p :if={!value.isEmpty}>{value}</p></li>")
        }
        let patch = try #require(page(["One", "Two"]).diff(to: page(["", "Two"])).keyed?["0"])
        #expect(patch.order == nil)
        #expect(Set(patch.entries.keys) == ["0"])
        #expect(patch.entries["0"]?.statics == ["<li></li>"])
    }

    @Test func invalidKeysFallBackWithoutDroppingRowsAndCanRecover() {
        func page(_ items: [Int]) -> ESWLiveRender {
            #live("<p :for={item in items} :key={item}>{item}</p>")
        }
        let valid = page([1, 2])
        let duplicates = page([1, 1])
        #expect(duplicates.html == "<p>1</p><p>1</p>")
        #expect(duplicates.keyed.isEmpty)
        #expect(valid.diff(to: duplicates).dynamics == ["0": "<p>1</p><p>1</p>"])
        let recovery = duplicates.diff(to: valid)
        #expect(recovery.dynamics == ["0": ""])
        #expect(recovery.keyed?["0"]?.entries.count == 2)
        let keys = [Double.nan]
        #expect(#live("<p :for={key in keys} :key={key}>Value</p>").html == "<p>Value</p>")
        #expect(#live("<p :for={key in keys} :key={key}>Value</p>").keyed.isEmpty)
    }

    @Test func keyedVariablesDoNotShadowTemplateValues() {
        let __esw_rows = ["<A>", "B"]
        let _buf = "&"
        let html = #live("<p :for={value in __esw_rows} :key={value}>{_buf}{value}</p>").html
        #expect(html == "<p>&amp;&lt;A&gt;</p><p>&amp;B</p>")
    }

    @Test(arguments: [
        #"{"statics":["",""],"dynamics":[""],"keyed":{"0":{"order":["a","a"],"entries":{}}}}"#,
        #"{"statics":["",""],"dynamics":[""],"keyed":{"0":{"order":["a"],"entries":{}}}}"#,
        #"{"statics":["",""],"dynamics":[""],"keyed":{"1":{"order":[],"entries":{}}}}"#,
        #"{"statics":["",""],"dynamics":["occupied"],"keyed":{"0":{"order":[],"entries":{}}}}"#,
    ])
    func decodingRejectsMalformedKeyedRenders(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ESWLiveRender.self, from: Data(json.utf8))
        }
    }

    @Test func patchesContainOnlyChangedDynamicValues() throws {
        func page(_ count: Int) -> ESWLiveRender { #live("<p>Count: {count}</p><p>Static</p>") }
        let first = page(1)
        let patch = first.diff(to: page(2))
        #expect(patch.statics == nil)
        #expect(patch.dynamics == ["0": "2"])
        #expect(first.html == "<p>Count: 1</p><p>Static</p>")
        #expect(try JSONDecoder().decode(ESWLiveRender.self, from: JSONEncoder().encode(first)) == first)
        #expect(first.diff(to: first).dynamics.isEmpty)
    }

    @Test func changingStaticShapeProducesAReset() {
        func page(_ items: [String]) -> ESWLiveRender { #live("<ul><li :for={item in items}>{item}</li></ul>") }
        let next = page(["<A>", "B"])
        #expect(page([]).diff(to: next).statics == next.statics)
        #expect(next.html == "<ul><li>&lt;A&gt;</li><li>B</li></ul>")
    }

    @Test func liveAndStringRenderingHaveIdenticalEscaping() {
        let title = "\"\u{301}<A>"
        let visible = true
        let live = #live("<p :if={visible} title={title}>{title}</p>")
        #expect(live.html == #heex("<p :if={visible} title={title}>{title}</p>"))
    }

    @Test func componentsKeepTypedDeferredSlotsAndEscaping() {
        func page(_ title: String) -> ESWLiveRender {
            #live("<.live-card title={title} :let={label}><p>{label}</p></.live-card>")
        }
        let title = "<Swift & HEEx>"
        let live = page(title)
        #expect(live.html == #heex("<.live-card title={title} :let={label}><p>{label}</p></.live-card>"))
        #expect(live.html == "<article><p>&lt;Swift &amp; HEEx&gt;</p></article>")
        #expect(live.diff(to: page("Changed")).statics == nil)
        #expect(live.diff(to: page("Changed")).dynamics == ["0": "<article><p>Changed</p></article>"])
    }

    @Test func decodingRejectsMalformedRenderShapes() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ESWLiveRender.self, from: Data(#"{"statics":[],"dynamics":[]}"#.utf8))
        }
    }
}
