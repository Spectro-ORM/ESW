import ESWLivePeregrine

struct DemoState: Sendable {
    var count = 0
    var name = ""
    var greeting = "Tell Peregrine your name."
    var rows = ["first", "second", "third"]
}

struct DemoView: Interactive {
    func mount(_ context: LiveContext) async throws -> DemoState { DemoState() }
    func handleEvent(_ event: LiveEvent, state: DemoState) async throws -> DemoState {
        var state = state
        switch event.name {
        case "increment", "server-increment": state.count += 1
        case "decrement": state.count -= 1
        case "reverse": state.rows.reverse()
        case "greet":
            state.name = event.value("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            state.greeting = state.name.isEmpty ? "Please enter your name." : "Hello, \(state.name)!"
        case "noop": break
        default: throw LiveError.invalidEvent
        }
        return state
    }
    func render(_ state: DemoState) -> ESWLiveRender {
        #live("""
        <main>
          <p class="eyebrow">Peregrine · ESW Live</p>
          <h1>Swift on the server.<br />Alive in the browser.</h1>
          <p class="intro">Click, type, and reorder. Swift owns the state; this page stays in place.</p>
          <section aria-label="Counter">
            <h2>A live counter</h2>
            <div class="counter"><button type="button" esw-click="decrement" aria-label="Decrease">−</button><output id="count" aria-live="polite">{state.count}</output><button type="button" esw-click="increment" aria-label="Increase">+</button></div>
          </section>
          <section aria-label="Form">
            <h2>A server-handled form</h2>
            <form id="greeting-form" esw-submit="greet"><label for="name">Your name</label><div class="form-row"><input id="name" name="name" value={state.name} autocomplete="off" /><button type="submit">Say hello</button></div></form>
            <p id="greeting" aria-live="polite">{state.greeting}</p>
          </section>
          <section aria-label="Keyed list">
            <div class="section-heading"><h2>Elements keep their identity</h2><button type="button" esw-click="reverse">Reverse</button></div>
            <ul id="rows"><li :for={row in state.rows} id={"row-" + row}><label for={"draft-" + row}>{row}</label><input id={"draft-" + row} placeholder="Keep a draft here" /></li></ul>
          </section>
        </main>
        """)
    }
}

@main
struct LiveDemo: PeregrineApp {
    static let live = PeregrineLive(DemoView())
    private let store = MemorySessionStore()
    var sessionStore: SessionStore? { store }
    var plugs: [Plug] { browserPlugs() }
    var server: ServerConfig { .fromEnvironment(defaultPort: 8097) }
    var routes: [Route] {
        GET("/") { conn in try await Self.live.render(conn, layout: Self.layout) }
        Self.live.routes
        // Development acceptance endpoint. The instance remains owner-bound
        // and browserPlugs applies CSRF before this server-originated update.
        POST("/server-update/:id") { conn in
            guard let owner = conn.getSession(PeregrineLive<DemoView>.ownerKey) else { throw LiveError.unauthorized }
            _ = try await Self.live.host.handle(conn.params["id"] ?? "", owner: owner, event: .init(name: "server-increment"))
            return conn.respond(status: .noContent, body: .empty)
        }
        POST("/invalidate") { conn in
            await Self.live.invalidate(conn)
            return conn.respond(status: .noContent, body: .empty)
        }
    }

    static func layout(_ html: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Peregrine Live</title>
        <style>
        :root{font-family:system-ui,sans-serif;color:#19272b;background:#f6f8f5}body{margin:0}main{max-width:720px;margin:64px auto;padding:0 24px 64px}.eyebrow{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.12em;color:#557066}h1{font-size:clamp(34px,6vw,52px);line-height:1.08;letter-spacing:-.045em;margin:20px 0}.intro{line-height:1.6;color:#5e706b;max-width:540px}section{border-top:1px solid #d8e0d8;padding:26px 0;margin-top:30px}h2{font-size:16px;margin:0 0 20px}button,input{font:inherit;border:1px solid #bccbc3;border-radius:7px;padding:10px 15px;background:white}button{cursor:pointer;background:#e9f0e9}button:hover{background:#dae7dc}button:focus-visible,input:focus-visible{outline:3px solid #68978b;outline-offset:3px}.counter{display:flex;align-items:center;gap:26px}.counter button{font-size:22px;width:52px}.counter output{font-size:42px;font-variant-numeric:tabular-nums;min-width:60px;text-align:center}label{font-size:14px;display:block;margin-bottom:8px}.form-row{display:flex;gap:12px}.form-row input{flex:1;min-width:0}#greeting{color:#49665b}.section-heading{display:flex;align-items:center;justify-content:space-between;gap:20px}.section-heading h2{margin:0}ul{padding:0;list-style:none}li{display:flex;align-items:center;gap:16px;border-top:1px solid #e4e9e1;padding:12px 0}li label{width:55px;margin:0}li input{flex:1;min-width:0}[data-esw-state=disconnected] main,[data-esw-state=expired] main{opacity:.65}@media(max-width:500px){main{margin-top:32px}.form-row{flex-direction:column}.section-heading{align-items:start}}
        </style></head><body>\(html)</body></html>
        """
    }
}
