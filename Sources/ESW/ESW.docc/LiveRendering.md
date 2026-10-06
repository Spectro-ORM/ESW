# Structured live rendering

Produce output snapshots and patches without coupling templates to an HTTP transport.

## Overview

### Render a snapshot

The ``live(_:)`` macro uses HTML-aware syntax and escaping, but returns
``ESWLiveRender`` instead of `String`:

```swift
import ESW

func counter(_ value: Int) -> ESWLiveRender {
    #live("<p>Count: {value}</p>")
}

let before = counter(1)
let after = counter(2)
let html = before.html
let patch = before.diff(to: after)
// html == "<p>Count: 1</p>"
// patch.statics == nil
// patch.dynamics == ["0": "2"]
```

The snapshot alternates literal spans with already-rendered dynamic slots:
`statics.count` is always `dynamics.count + 1`. Use `.html` for an initial page
fragment and `.snapshot` when a receiver needs the entire representation.

If the next render has identical statics, `.diff(to:)` returns only changed
dynamic indices. Indices use decimal strings in the codable patch. A changed
static shape causes a full snapshot; a no-op produces an empty dynamic map and no
keyed updates. Keyed slots use an empty dynamic string and a separate `keyed` entry.

### Keyed comprehensions

```html
<li :for={item in items} :key={item.id} id={"item-\(item.id)"}>{item.name}</li>
```

Each keyed comprehension occupies a stable dynamic slot. Its patch contains an
optional replacement row order and only changed row entries. Reordering sends no
unchanged row content, inserting sends the new row, and edits recursively diff
the affected row. Nested keyed lists use independent identity scopes. Replacing
a slot with a dynamic string clears its previous keyed value.

Use stable `Encodable` keys with unique JSON encodings within each list, such as
integers, strings or UUIDs. Duplicate or unencodable keys preserve all output by
falling back to a full HTML fragment. `:key` requires `:for` on the same element
or function component; slots do not support it. String templates accept the same
syntax and render ordinary HTML.

### What changes are tracked

Every Swift template expression runs on every render. The patch compares output
strings; it does not track which state properties an expression reads.
Branches and unkeyed variable-length loops may change the shape. A string-returning
component is one opaque dynamic fragment, although its own slot bodies still
render normally.

Stable HTML `id` attributes help the browser preserve elements during DOM
reconciliation. `:key` controls wire diffing separately and does not emit an HTML
attribute or synthesize a DOM ID. Serve the Swift runtime and browser assets from
the same version.

### File templates

The build plugin recognizes the full `.live.hesw` suffix. Without an associated view,
`counter.live.hesw` becomes `renderCounterLive(...) -> ESWLiveRender`. With a
view annotated `@ESWTemplate("counter.live.hesw")`, its `render()` method returns the same
type. See <doc:FileTemplates>.

Ordinary `.hesw` and `.esw` renderers return strings. `#render("counter.live.hesw")`
also returns `String`; use the build plugin or `#live` for structured output.

### State and transport

The `ESWLive` product adds an `Interactive` protocol, serialized actor sessions,
revisioned events, and owner-bound instance registries. It is a separate library
so plain template rendering needs no stateful runtime.

Its browser client expects an adapter to serve an initial root, JavaScript
modules, an SSE stream, and POST events. Authentication, CSRF, HTTP responses,
and server resource management belong at that boundary. Importing `ESWLive`
alone does not install routes.

The package's library documentation includes an `ESWLive` module guide with a
working session example and the adapter contract. The repository's
`Documentation/LiveView.md` describes the existing development adapter; Roost
Playground provides a separate runnable integration.
