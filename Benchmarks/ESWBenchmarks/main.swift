import ESW

// Run with: swift run -c release ESWBenchmarks

struct Row {
    let id: Int
    let name: String
    let email: String
    let note: String?
}

// A quarter of the names need escaping; a third of the notes are nil.
let rows = (0..<1_000).map { i in
    Row(id: i,
        name: i % 4 == 0 ? "O'Brien & Sons <\(i)>" : "Customer \(i)",
        email: "user\(i)@example.com",
        note: i % 3 == 0 ? nil : "Plain note \(i)")
}

func table(_ rows: [Row]) -> String {
    #hesw("""
    <table>
      <tr :for={row in rows}>
        <td>{row.id}</td><td title={row.email}>{row.name}</td><td>{row.note}</td>
      </tr>
    </table>
    """)
}

func liveTable(_ rows: [Row]) -> ESWLiveRender {
    #live("""
    <table>
      <tr :for={row in rows} :key={row.id}>
        <td>{row.id}</td><td title={row.email}>{row.name}</td><td>{row.note}</td>
      </tr>
    </table>
    """)
}

// Lower bound: the same markup without escaping or template machinery.
func unescaped(_ rows: [Row]) -> String {
    var html = "<table>"
    for row in rows {
        html += "<tr><td>\(row.id)</td><td title=\"\(row.email)\">\(row.name)</td><td>\(row.note ?? "")</td></tr>"
    }
    return html + "</table>"
}

func measure(_ name: String, iterations: Int = 300, _ body: () -> Int) {
    var bytes = 0
    for _ in 0..<20 { bytes &+= body() }
    var samples: [Duration] = []
    for _ in 0..<iterations {
        let start = ContinuousClock.now
        bytes &+= body()
        samples.append(ContinuousClock.now - start)
    }
    samples.sort()
    func microseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return "\(Int((Double(seconds) * 1e6 + Double(attoseconds) / 1e12).rounded())) µs"
    }
    print("\(name): median \(microseconds(samples[iterations / 2])), min \(microseconds(samples[0]))  [\(bytes / (iterations + 20))]")
}

measure("HESW table, 1,000 rows") { table(rows).utf8.count }
measure("Unescaped interpolation") { unescaped(rows).utf8.count }

// One live event: render the next state and diff it against the current one.
var edited = rows
edited[500] = Row(id: 500, name: "Changed", email: "changed@example.com", note: nil)
let current = liveTable(rows)
measure("Live table, 1,000 keyed rows") { liveTable(rows).dynamics.count }
measure("Live render + diff, one row changed") { current.diff(to: liveTable(edited)).keyed?.count ?? 0 }
