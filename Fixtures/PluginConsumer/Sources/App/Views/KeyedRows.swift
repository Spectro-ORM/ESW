import ESW
import Foundation

struct KeyedRow {
    let id: Int
    let name: String
}

@ESWTemplate("keyed-rows.live.heex")
struct KeyedRows {
    let rows: [KeyedRow]
}

// Shared wire fixtures exercise the real Swift compiler and JSON encoder in Node
// and in the browser, without requiring a particular HTTP framework adapter.
struct KeyedWireUpdate: Encodable {
    let revision: Int
    let baseRevision: Int?
    let render: ESWLivePatch
    let expectedHTML: String
}

func keyedWireFixture() throws -> String {
    let states: [[(Int, String)]] = [
        [(1, "One"), (2, "Two")],
        [(3, "Three"), (1, "One"), (2, "Two")],
        [(2, "Two"), (3, "Three"), (1, "One")],
        [(2, "<Changed>"), (3, "Three"), (1, "One")],
        [(2, "<Changed>"), (1, "One")],
        [],
        [(1, "Restored"), (2, "Two")],
        [(1, "First"), (1, "Second")],
        [(1, "First"), (2, "Two")],
    ]
    let renders = states.map { state in
        KeyedRows(rows: state.map { KeyedRow(id: $0.0, name: $0.1) }).render()
    }
    let updates = renders.enumerated().map { index, render in
        KeyedWireUpdate(revision: index + 1, baseRevision: index == 0 ? nil : index,
                        render: index == 0 ? render.snapshot : renders[index - 1].diff(to: render),
                        expectedHTML: render.html)
    }
    return String(decoding: try JSONEncoder().encode(updates), as: UTF8.self)
}
