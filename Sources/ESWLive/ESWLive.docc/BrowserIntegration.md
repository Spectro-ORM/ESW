# Browser and HTTP integration

Connect a live host to the bundled browser client through authenticated routes.

## Overview

### Adapter responsibilities

An adapter owns a stable ``LiveHost`` and connects it to the web framework:

1. Authenticate and authorize the initial request, obtain a trusted owner token,
   and call `host.mount(owner:context:)`.
2. Render the returned HTML inside a root with a stable `id`, `data-esw-live`,
   `data-esw-id`, `data-esw-stream`, `data-esw-event`, and `data-esw-csrf` attributes.
   Escape all attribute values. Initially set `data-esw-state="connecting"`.
3. Serve all modules supplied by ``LiveAssets/javascript(named:)`` as JavaScript,
   keeping `esw-live.js` and its relative `live-render.js` / `idiomorph.js` imports together. Include
   `esw-live.js` with `<script type="module" ...>`.
4. Reauthorize stream and event requests, check ownership, and protect event POSTs
   against CSRF. Validate JSON content type, body size, and a nonnegative base revision.
5. Forward `host.subscribe` updates as SSE messages named `update`, with JSON data.
   Return the same codable `LiveUpdate` as the POST event response.
6. Close streams and shut down the host when the server stops. Invalidate the
   owner's instances on logout or permission revocation.

Keep stream/event URLs on the same origin as the page. Send full snapshots on
reconnect. Apply bounded forwarding queues and await network writes; the session's
buffer limit alone does not bound every queue in an HTTP adapter. A missing or
expired stream should return HTTP 204 so EventSource stops retrying.

The development adapter uses a 64 KiB POST-body limit and 15-second SSE comment
heartbeats. These are adapter choices, separate from the Swift event-value limit.
Avoid exposing server exception details in browser error responses.

### Declarative bindings

| Binding | Behavior |
| --- | --- |
| `esw-click="increment"` | Sends a click event; modified clicks keep browser behavior. |
| `esw-value-id="123"` | Adds `values["id"] == ["123"]` to that click. |
| `esw-submit="save"` on a form | Sends successful fields and the submitter without navigation. |
| `esw-change="validate"` on a form or control | Sends input/change events, debounced by 150 ms by default. |
| `esw-debounce="300"` | Changes that delay; clamped to 0–5,000 ms. |
| `esw-ignore` | Preserves an existing element's attributes and children during morphing. Its parent can still remove it. |

```html
<form id="profile" esw-submit="save" esw-change="validate">
  <label for="name">Your name</label>
  <input id="name" name="name" value={name} />
  <button type="submit">Save</button>
</form>
```

Use stable IDs for forms, controls, and reorderable rows. The client preserves
focus, selection, and dirty control values. Acknowledgements release edits included
in their event; newer edits stay protected. These bindings do not provide file
uploads, nested form decoding, or Phoenix `_target` metadata.

### JavaScript access

```javascript
import { connectLiveViews } from "/_live/assets/esw-live.js";

const client = connectLiveViews()[0];
client.push("refresh");
client.root.addEventListener("esw:error", event => {
  console.error(event.detail.message);
});
```

The asset prefix above is an adapter convention; use the route installed by your
application. `connectLiveViews()` reuses existing clients for roots it has already
connected. Events queue until a connection is ready, with a 64-event browser limit.

The root exposes `data-esw-state`, `data-esw-revision`, and `aria-busy`, plus
`esw:status`, `esw:update`, and `esw:error` custom events. Listen on the root because
these events do not bubble. Controls are not automatically disabled.

A native form reset or `client.resetForm(form)` restores the most recent server
values and cancels unsent debounced changes. It does not cancel queued or sent
events. Call `client.dispose()` before removing a root yourself. Normal page
teardown disposes clients, and back/forward-cache restoration reconnects them.
An expired instance requires a page reload rather than a silent state reset.

### Existing applications

[Roost Playground](https://github.com/roost-framework/roost-playground) contains an adapter
for the renamed Roost framework. The `Integrations/PeregrineLive` package in this
repository still targets the earlier Peregrine module and needs a compatible
checkout. These integrations use ESW's protocol; the Phoenix JavaScript client
cannot connect to it.
