# Live rendering: evidence and first slice

Researched 2026-10-04 against Phoenix LiveView 1.2.12, Phoenix 1.8.15, the HTML Standard, Swift SE-0306, Idiomorph 0.8.0, and the adjacent Nexus/Peregrine checkouts. This is a design evidence note; implementation and acceptance results belong in [LiveView.md](LiveView.md).

The selected first slice is a transport-independent `ESWLive` session, compiled `#live` render captures, and a separate Peregrine adapter using SSE updates plus POST events. It should deliver an initial HTML page, interactive counter/form, server-initiated updates, and reconnection with bounded resources. Phoenix supplies semantic references; this protocol does not interoperate with the Phoenix JavaScript client.

## What Phoenix actually guarantees

| Area | Primary-source behavior | Consequence for ESW |
| --- | --- | --- |
| Mount | HTTP rendering runs `mount`, `handle_params`, and `render`. Connecting starts a stateful process and runs the lifecycle again. Reconnection after a dropped connection or crash remounts. Browser params are public; session data comes from the application. [LiveView lifecycle](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-life-cycle). | Make disconnected and connected mount explicit. Rendering a page must work before JavaScript. Mount must tolerate repeated execution; put subscriptions in the connected phase and avoid irreversible effects during mount. |
| Render representation | `Rendered` separates static spans, a dynamic function, and a fingerprint. Dynamics may contain unchanged markers, nested renders, comprehensions, and components. Change tracking can skip evaluations, while fingerprints distinguish templates. [Engine](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Engine.html). | A static/dynamic output diff is useful independently of dependency tracking. Do not describe evaluating every Swift expression and comparing strings as Phoenix-style computation skipping. |
| Diff application | A matching render fingerprint permits reuse of previous structure. New static content replaces that render subtree; otherwise the client merges dynamic entries. This is a render-tree protocol followed by DOM reconciliation. [Server diff](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/diff.ex), [client render merge](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/assets/js/phoenix_live_view/rendered.js). | Missing or incompatible render structure requires a snapshot. Dynamic indices are meaningful only against their matching static shape and base revision. |
| Events and acknowledgements | The LiveView channel is a GenServer receiving event messages with an event name, type, and value. A referenced event receives an acknowledgement even when the resulting diff is empty; a changed render can be included in the reply. [Channel source](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/channel.ex). | Every admitted event needs a terminal outcome, including no-ops and failures. Render changes alone cannot drive loading-state completion. |
| Forms | Form-level change bindings serialize the form; `_target` identifies the triggering field. The client uses `FormData` and appends entries, retaining repeated names and the submitter. File handling is separate. Forms with IDs and change bindings can recover values after reconnect. [Form bindings](https://hexdocs.pm/phoenix_live_view/form-bindings.html), [serialization source](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/assets/js/phoenix_live_view/view.ts). | Preserve repeated values and submitter data. A counter alone does not validate the event layer. Do not silently claim upload or automatic form-recovery support. |
| DOM and pending input | The browser owns current input values. LiveView tracks events in flight per element/form and delays conflicting patches until acknowledgements permit them. Its DOM patcher captures focus/selection and normally protects the focused input's value. [Synchronization](https://hexdocs.pm/phoenix_live_view/syncing-changes.html), [DOM patch source](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/assets/js/phoenix_live_view/dom_patch.ts). | Revision ordering and focus restoration are insufficient by themselves: old validation output must not overwrite newer edits, including after focus moves. |

Phoenix requires authentication checks in both HTTP handling and connected mount, plus authorization where resources are accessed in parameters or events. Its transport can validate a cookie session with a CSRF token; LiveView verifies signed session/static tokens and checks their view identity. These are distinct checks, not substitutes for per-event authorization. [Security model](https://hexdocs.pm/phoenix_live_view/security-model.html), [Phoenix transport](https://raw.githubusercontent.com/phoenixframework/phoenix/v1.8.15/lib/phoenix/socket/transport.ex), [LiveView session verification](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/session.ex).

## Why use the existing HTTP path first

Peregrine's `channel(...)` endpoint currently returns a placeholder response; `Channel` creates fresh handlers rather than owning persistent view state. Nexus has WebSocket adapters, but that does not make Peregrine browser channels complete. SSE avoids coupling this slice to that unfinished integration. [Channel endpoint](../../Peregrine/Sources/Peregrine/Channels/ChannelPlug.swift), [channel lifecycle](../../Peregrine/Sources/Peregrine/Channels/Channel.swift).

Nexus already exposes `Connection.sseEvent`, backed by a lazy response producer. Awaiting each writer call supplies transport backpressure; the writer must remain inside the producer. Headers request no caching/transformation and disable supported proxy buffering. Supplied `AsyncThrowingStream` buffering remains the caller's responsibility. Peregrine flushes session persistence before the response is sent, and its CSRF plug protects JSON requests by default. [SSE](../../Nexus/Sources/Nexus/SSE.swift), [writer](../../Nexus/Sources/Nexus/ResponseBodyWriter.swift), [body](../../Nexus/Sources/Nexus/Body.swift), [request pipeline](../../Peregrine/Sources/Peregrine/RequestPipeline.swift), [CSRF](../../Peregrine/Sources/Peregrine/CSRFPlug.swift).

The SSE standard requires UTF-8 `text/event-stream` and blank-line event termination. `EventSource` reconnects automatically and sends `Last-Event-ID` when available; HTTP 204 tells it to stop. Its constructor provides URL and credentials configuration, not arbitrary request headers. Comment heartbeats around every 15 seconds are recommended against idle proxy timeouts. [HTML SSE standard](https://html.spec.whatwg.org/multipage/server-sent-events.html).

For this adapter, use same-origin cookies and authorize the stream GET through the application pipeline. Send the page's CSRF token on event POSTs; keep JSON CSRF protection enabled. Treat `Last-Event-ID` as advisory because this slice reconnects with a full snapshot rather than promising durable replay. Await heartbeat writes so disconnect errors can terminate the producer. Header settings alone do not prove streaming through the deployed proxy.

## First-slice contract

These are implementation requirements derived from the evidence above and the selected architecture, not claims that Phoenix uses this wire format.

### Rendering and protocol

- Keep `statics.count == dynamics.count + 1`. Interleave the spans to reconstruct HTML. Compare static arrays exactly: equal shapes send changed dynamic indices; different shapes send a complete snapshot. The current representation is [ESWLiveRender](../Sources/ESW/LiveRender.swift).
- Preserve the compiler's escaping boundary: captures contain already-escaped values or explicit trusted raw output. JSON encoding must neither unescape those values nor double-escape them. Client event values enter Swift state and pass through normal rendering; they are never HTML instructions. [ESW escaping](../Sources/ESW/Escape.swift).
- Give each update a revision, a base revision for deltas, and an optional originating event ID. Apply a delta only to its exact base. Ignore duplicate/older updates and request a snapshot on a gap. Validate index bounds and snapshot shape before replacing the client render cache.
- Include the same committed patch in the POST acknowledgement and SSE publication. Either can arrive first. Apply it once; clear pending state only after processing the corresponding acknowledgement and its render result, or a terminal error. An empty patch still acknowledges the event.

All dynamic expressions are evaluated on each render. Conditional branches and unkeyed list-size changes may replace the surrounding shape. The subsequent `:key` implementation keeps a comprehension in one dynamic slot and recursively diffs rows by identity, including nested keyed lists. This remains ESW's own wire protocol, without assign dependency analysis or a general component render tree.

### State, ordering, and recovery

Swift actors prevent simultaneous isolated access, but async methods may interleave across `await`, and actor scheduling is not FIFO. Therefore an actor alone does not serialize complete async event transactions. [Swift SE-0306](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy).

Use one explicit event queue per instance, with client requests serialized in user-event order. Each dequeued handler produces a state result; commit state, render, revision, and publication together before starting the next handler. Readers should see committed state while a handler awaits. Server-initiated changes enter the same ordering mechanism.

Deduplicate event IDs for the instance's documented lifetime/window, including pending requests. A retry with the same ID must reuse the outcome; reject reuse with a different payload. A lost HTTP response is ambiguous: retain its ID for retry. Bounded in-memory deduplication does not establish durable exactly-once effects across expiry or process restart.

Register a stream and capture its initial snapshot atomically with respect to committed updates, so no mutation falls between those operations. Reconnection receives a full current snapshot of the retained instance. A new stream generation must invalidate old callbacks and must not be removed by an older stream's cleanup. If a bounded subscriber queue drops a delta, replace it with a snapshot or terminate and reconnect; never continue a broken delta chain.

Limit instance count, idle lifetime, event payload/queue sizes, and stream buffering. Cancel subscriptions and release resources on stream termination. Expired instances require an explicit reload/remount outcome. Retaining an actor across a short disconnect is an intentional difference from Phoenix's documented remount lifecycle; it does not survive server restart.

### Session and browser behavior

Bind the unpredictable instance identifier to the server session that created it. Load identity from that session, authorize stream/event access, and authorize domain operations inside handlers. Establish cookies before streaming begins. Existing streams do not rerun request middleware on every update: applications that revoke access must invalidate/close the associated live instance rather than merely delete a cookie.

Use `esw-click`, `esw-change`, `esw-submit`, and `esw-value-*` for the bounded event vocabulary. Serialize successful form entries without collapsing repeated names; capture the submitter. Report unsupported files explicitly. Restore disabled/read-only/loading state after acknowledgement, no-op, or error while preserving any pre-existing disabled state.

Vendor and locally serve Idiomorph 0.8.0. Its `restoreFocus` defaults to true, but `ignoreActiveValue` defaults to false: enable value protection explicitly and give forms/controls/list items stable IDs. These options attempt to retain focus and selection; they do not implement LiveView's pending-event rules. Track dirty/pending values, including blurred controls, and retain newer local edits across unrelated or older patches. A deliberate form reset needs an explicit way to accept server values. [Idiomorph options](https://raw.githubusercontent.com/bigskysoftware/idiomorph/v0.8.0/README.md).

Keep bootstrap metadata in escaped HTML attributes, or escape `<` when embedding JSON in a script data block. JSON escaping alone does not prevent an HTML `</script>` terminator; data-block scripts still obey HTML script-content restrictions. [HTML script restrictions](https://html.spec.whatwg.org/multipage/scripting.html#restrictions-for-contents-of-script-elements).

## Evidence required before calling the slice complete

1. Real browser: initial HTML without JavaScript, counter and form events, server push, validation output, repeated field names, and submitter identity.
2. Render fixtures: unchanged output, changed dynamic positions, branch/list shape replacement, and hostile text/attribute values remain correct and escaped.
3. Ordering: two handlers with deliberate suspension cannot lose updates; duplicate IDs execute once within the supported window; no-op/error acknowledgements terminate loading; POST/SSE arrival order does not change the result.
4. Recovery: reconnect during mutation, a revision gap, a slow consumer, and an expired instance produce a snapshot or explicit reload, with bounded retained resources.
5. Browser state: typing followed by blur during a delayed response, selection, checked/select values, keyed row movement, and unrelated updates preserve the intended local state. Also test a deliberate reset.
6. Access: a second session, missing/invalid CSRF, malformed events, and invalidated instances fail before protected mutations; teardown closes subscriptions.

Passing this slice demonstrates a Swift live-rendering path for Peregrine. It does not establish Phoenix wire compatibility, distributed session durability, or comparable performance; those claims require separate implementation and evidence.
