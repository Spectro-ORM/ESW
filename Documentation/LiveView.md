# Live rendering for Peregrine

> Integration status: the adapter in this guide still imports the earlier
> `Peregrine` module. It needs a compatible framework checkout; the renamed
> `Roost` product alone does not satisfy that dependency. For current library
> APIs, start with the [ESWLive documentation](../Sources/ESWLive/ESWLive.docc/ESWLive.md).
> [Roost Playground](https://github.com/Maartz/roost-playground) provides the separate
> integration for the renamed framework. Validation results below are historical.

ESW can now render a page from Swift state, handle browser events, and update the DOM without navigation. This is an initial implementation using SSE updates and POST events. It runs in one server process and uses its own protocol.

## Run the example

The development adapter expects `esw`, `Peregrine`, and `Nexus` as sibling checkouts. From this repository:

```bash
./scripts/live_demo.sh
```

Open `http://localhost:8097`. `PEREGRINE_HOST` and `PEREGRINE_PORT` override the address. The [example](../Integrations/PeregrineLive/Examples/LiveDemo/main.swift) includes a counter, a form with server validation/normalization, and a reorderable list with local drafts. Its `/server-update/:id` route is a development probe protected by the browser session and CSRF pipeline.

The launcher keeps SwiftPM build products in `~/Library/Caches/esw-live/<checkout-id>` on macOS. This avoids the code-signing failure caused by `com.apple.FinderInfo` attributes on generated resource bundles in file-provider-managed folders such as `Documents`. The checkout itself stays in place, and normal code signing remains enabled. Apple documents the rejected metadata in [QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html). Override the build directory with `ESW_LIVE_SCRATCH_PATH` if needed; choose a local, unsynced directory. The browser harness uses the same launcher to locate the executable.

Use `./scripts/live_demo.sh build` to build without starting the server, `test` for adapter tests, and `bin-path` to print the executable directory. Additional SwiftPM options can follow the action, for example `./scripts/live_demo.sh run --skip-build`.

The adapter package has local dependencies intentionally. Publishing it requires coordinating package identities and versions with Peregrine/Nexus. SwiftPM currently warns about the local dependencies overriding Peregrine's remote identities and the upstream SwiftSyntax URL difference; these are not release validation results.

## A typed live view

```swift
import ESWLive

struct Counter: LiveView {
    func mount(_ context: LiveContext) async throws -> Int { 0 }

    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }

    func render(_ count: Int) -> ESWLiveRender {
        #live("<button esw-click=\"increment\">Count: {count}</button>")
    }
}
```

`State` is any `Sendable` type; value types make state transitions straightforward. Mount and handlers can await I/O; template evaluation itself is synchronous. A handler returns the next state. Throwing leaves the previous state and HTML intact. Authorize domain operations inside handlers, and use transactions/idempotency where external effects require them.

`LiveContext.parameters` and `.session` are explicitly supplied by trusted server code. They are not merged with browser event values. `isConnected` is false for the initial HTTP render and true for the first stream mount. Mount must tolerate both calls. Reconnecting to an existing instance reuses its connected state and sends a fresh snapshot; a reload creates a new instance.

For file templates, the existing build plugin recognizes `Views/counter.live.heex` and generates `renderCounterLive(...) -> ESWLiveRender`. Parameters, imports, HTML checking, escaping, components, and typed slots work as in ordinary HEEx files. `#live` is the inline equivalent. Normal `.heex`/`.esw` functions still return `String`; `#render` remains a String macro.

## Add it to a Peregrine app

Add the local integration package and its `ESWLivePeregrine` product to the application's `Package.swift`. Keep a stable adapter instance and a server-side session store:

```swift
import ESWLivePeregrine

@main
struct App: PeregrineApp {
    static let live = PeregrineLive(Counter())
    private let store = MemorySessionStore()
    var sessionStore: SessionStore? { store }
    var plugs: [Plug] { browserPlugs() }

    var routes: [Route] {
        GET("/") { conn in
            try await Self.live.render(conn, layout: { html in
                "<!doctype html><html lang=\"en\"><body>\(html)</body></html>"
            })
        }
        Self.live.routes
    }
}
```

The adapter serves `/_live/assets/:name`, `/_live/:id/stream`, and `/_live/:id/event`. Multiple view types need separate adapter paths. `render` emits the live root and an external module script; browser assets are bundled locally, including [Idiomorph 0.8.0 and its license](../Sources/ESWLive/Resources/ThirdParty.md).

Every instance belongs to a random owner token in the creating server session. A second session cannot connect or send events to it. The adapter checks POST CSRF itself even if the surrounding app omits `browserPlugs`. Keep the normal browser pipeline enabled for the rest of the app.

Use the `authorize` initializer closure to check access at HTTP mount and on each stream/event request; throw `LiveError.unauthorized` to deny access. Already-open streams do not rerun middleware for each update. Call `await live.invalidate(conn)` **before clearing the session** on logout or permission revocation. This closes existing streams and rejects mounts that were suspended when invalidation happened. Domain authorization still belongs in the event handler.

`live.host.send(id, event: LiveEvent(name: "refresh"))` delivers a trusted server event through the same queue and renderer. It bypasses browser ownership checks and must only be called from trusted application code. `host.shutdown()` permanently closes a host; per-owner invalidation permits a later freshly authorized mount.

## Browser bindings

| Binding | Behavior |
| --- | --- |
| `esw-click="increment"` | Sends a click event; modified clicks retain browser behavior. |
| `esw-value-id="123"` | Adds `values["id"] == ["123"]` to the click payload. |
| `esw-submit="save"` on a form | Serializes successful fields and the submitter without navigation. |
| `esw-change="validate"` on a form/control | Sends input/change events, debounced by 150 ms by default. |
| `esw-debounce="300"` | Configures the change delay in milliseconds, bounded to 0–5000. |
| `esw-ignore` | Preserves an existing element's attributes and contents during morphing. Its parent can still remove it. |

Read `event.value("name")` for the first field value or `event.values["choice"]` for repeated fields. Bracketed names remain strings; this layer does not decode nested form structures. File uploads are explicitly rejected. Change events do not currently include Phoenix's `_target` metadata.

Give forms, controls, and reorderable rows stable HTML IDs. The client preserves focus, selection, and dirty control values, including blurred controls. An acknowledgement releases only edits included in that event; newer edits remain protected. A native form reset, or `client.resetForm(form)`, restores the most recently rendered server values and cancels unsent debounced changes. It does not cancel events already sent or queued. Ignored regions are appropriate for independently managed widgets, not nested live views.

The live root exposes `data-esw-state`, `data-esw-revision`, and `aria-busy`. Subscribe directly to its `esw:status`, `esw:update`, and `esw:error` events for application UI. These custom events do not bubble. `esw:error` contains `detail.message`; no server exception details are sent to the browser. Controls are not automatically disabled. A no-op event still receives an acknowledgement and clears loading.

```javascript
import { connectLiveViews } from "/_live/assets/esw-live.js";
const client = connectLiveViews()[0];
client.push("refresh");
client.root.addEventListener("esw:error", event => {
  console.error(event.detail.message);
});
```

Page teardown disposes clients; a page restored from the browser's back/forward cache reconnects. Code removing a live root directly should call `client.dispose()` first. An expired instance reports `expired` and requires a reload; it is not silently remounted with lost state.

## Rendering, ordering, and recovery

`ESWLiveRender` separates literal spans from already-escaped dynamic values and keyed comprehensions. Its `html` property reconstructs them. Equal static arrays produce a patch containing only changed dynamic indices; different shapes send a complete snapshot. Branches and unkeyed variable-length lists can change the shape. String-returning components are opaque dynamic fragments, while their typed slot closures still render normally.

Use `:for={item in items} :key={item.id}` on an HTML element or function component for keyed wire-level list diffs. Each comprehension occupies one dynamic slot. Its `keyed` patch contains an optional replacement `order` and only changed `entries`; existing rows are recursively diffed, new rows receive snapshots, and omitted identities in a replacement order are deleted. Nested keyed lists are supported. A string update clears any previous keyed value at that slot. Keys must be stable, unique `Encodable` values; duplicate or unencodable keys fall back to a full HTML fragment. `:key` needs `:for` and is rejected on slots.

Every Swift expression is still evaluated on render. There is no assign dependency tracking or general component render tree. `:key` does not generate an HTML attribute; explicit stable `id` attributes preserve DOM nodes in Idiomorph. Serve the bundled browser assets and Swift runtime from the same version so the client understands keyed patches.

An explicit queue serializes each entire async handler, state commit, and publication. Actor isolation alone would permit interleaving across suspension points. Successful events produce a revision, base revision, event ID, and patch. SSE and POST carry the same result and may arrive in either order; the browser applies the render once.

The host caches the last 128 admitted event outcomes, including handler failures. Retrying an ID with the identical payload returns its original result; changing its payload is rejected. Browser events require a base revision. Every admitted handler outcome consumes a revision, including failures, so an evicted old request cannot execute again. A failed handler publishes an empty update without acknowledging dirty fields. Pre-admission errors (such as a stale revision or full queue) do not consume a revision.

The browser retains IDs after lost responses or truncated JSON bodies. It reconnects with a full snapshot and retries the same event. Cached acknowledgements reconcile normalized form values even if the snapshot arrived first. A gap, malformed update, or rejected event triggers a bounded reconnect delay. Explicit event failures are surfaced rather than silently reissued with new IDs. Accepted mutations continue after HTTP request cancellation; retries can retrieve their result.

SSE sends UTF-8 JSON events and 15-second comment heartbeats. Writers await socket writes. Slow consumers are disconnected when bounded queues fill and recover with a snapshot; this implementation does not promise replay using `Last-Event-ID`. Missing/expired instances return HTTP 204 to stop EventSource reconnection. The protocol is transport-independent at the session layer; a future WebSocket adapter can reuse it.

## Resource limits

| Resource | Default |
| --- | --- |
| Instances per host, including pending mounts | 1000; configurable |
| Instance lifetime | One hour from mount; configurable, not extended by activity |
| Pending session operations | 32; configurable on `LiveSession` |
| Session update queue / HTTP forwarding queue | 16 entries each |
| Browser event queue | 64 events |
| Remembered event outcomes | 128 per instance |
| POST body / aggregate event values | 64 KiB |
| Event ID / event name | 128 UTF-8 bytes each |
| Field names / values per field | 128 each; keys at most 256 UTF-8 bytes |

Expired or invalidated instances close streams and cancel pending work before it can commit further state. Swift cancellation is cooperative: application I/O and user-created background tasks still need their own cancellation/resource management. The runtime cannot roll back external side effects.

## Validation

Run from the repository root:

```bash
swift test
python3 scripts/check_integration.py --peregrine ../Peregrine
./scripts/live_demo.sh test
./scripts/live_demo.sh build
npm ci --prefix BrowserTests
npm test --prefix BrowserTests
npm run test:keyed --prefix BrowserTests
```

Verified on 2026-10-04: 253 core Swift tests and 2 adapter tests passed, along with the compiler integration script and the real-browser suite. The demo screenshot was visually reviewed.

The independent `test:keyed` suite compiles the Swift build-plugin fixture and applies its encoded patches in JavaScript and a real browser. It verifies insertion, reordering, row edits, deletion, empty lists, fallback/recovery, malformed-patch rejection, and preservation of focused draft inputs and selection. It also runs the existing form/DOM client regressions. This suite does not require the legacy Peregrine adapter.

The browser harness uses installed Google Chrome on macOS, or Playwright Chromium otherwise (`cd BrowserTests && npx playwright install chromium`). It starts its own loopback server on a free port and shuts it down. The screenshot is written to `BrowserTests/artifacts/live-demo.png`.

Coverage includes compiled live templates and typed slots, escaping, dynamic/shape changes, concurrent suspended handlers, successful/failed retry deduplication, cache eviction, queue capacity, cancellation, owner isolation, CSRF, payload validation, invalidation during suspended mount, expiry, and reconnect. Real browser checks cover SSR, clicks, forms, submitters, repeated fields, focus/selection, keyed rows, dirty text/checkbox/select/textarea values, reset, ignored DOM, offline recovery, lost/truncated acknowledgements, no-op/error completion, and revision gaps. In-process Peregrine tests check route/security behavior; writer-based SSE is validated over real HTTP in the browser harness.

## Boundaries

This does not implement Phoenix wire compatibility, cross-node session storage, uploads, nested stateful live components, live navigation, async template expressions, user-task lifecycle hooks, or template dependency tracking. State and retry history do not survive process restart. Distributed deployment needs sticky routing or a shared live-session design. Hosted proxy behavior, Linux, and comparative performance have not been validated here.

See [the primary-source research](LiveViewResearch.md) for the lifecycle, protocol, and DOM decisions behind this implementation.
