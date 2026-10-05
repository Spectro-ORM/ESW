# Writing a live view

Describe state transitions in Swift and render them with an ESW live template.

## Overview

### Add the runtime

Add `.product(name: "ESWLive", package: "esw")` to your application target using
the local development ESW dependency. `import ESWLive` also makes `ESW` available.
The current package requires Swift 6.3+ and macOS 14+.

### Define the view

```swift
import ESWLive

struct Counter: LiveView {
    func mount(_ context: LiveContext) async throws -> Int { 0 }

    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }

    // swiftformat:disable:next unusedArguments
    func render(_ count: Int) -> ESWLiveRender {
        #live("""
        <section>
          <output id="count">{count}</output>
          <button type="button" esw-click="increment">Add one</button>
        </section>
        """)
    }
}
```

The view and its associated state must be `Sendable`. Prefer value types for
state; return a new value from each event handler. Mount and handlers can await
I/O. Rendering is synchronous. Authorize domain operations in the handler before
performing external effects.

The formatter guard prevents SwiftFormat from removing a binding referenced only
inside the template string.

### Exercise it without an HTTP server

```swift
func exerciseCounter() async throws {
    let session = try await LiveSession(view: Counter())
    let connected = try await session.connect()
    let event = LiveEvent(
        id: "increment-1",
        name: "increment",
        baseRevision: connected.revision
    )

    let update = try await session.handle(event)
    let retried = try await session.handle(event)
    precondition(update == retried)

    let html = await session.html
    print(html)
    await session.close()
}
```

The identical retry returns its remembered outcome rather than incrementing
again. The example deliberately supplies a base revision so a delayed retry is
also rejected after its remembered outcome has been evicted.

### Read form values

Fields arrive as `[String: [String]]`. Use ``LiveEvent/value(_:)`` for a single
value and `event.values["tag"]` for repeated values:

```swift
let submittedName = event.value("name") ?? ""
let selectedTags = event.values["tag"] ?? []
```

These are browser inputs, separate from ``LiveContext/session``. Validate and
normalize them in the handler. Bracketed field names are not decoded into nested
objects, and the bundled client rejects file uploads.

### Connect it to an application

For a one-file application, the separate
[Roost Playground](https://github.com/Maartz/roost-playground) supplies the server
and browser shell using the renamed Roost framework. It requires the same local
development dependencies as this runtime.

For your own integration, use <doc:BrowserIntegration> to implement the HTTP
boundary around ``LiveHost``. The repository's historical `ESWLivePeregrine`
adapter is reference code for that boundary; it still names the old Peregrine
product and is not interchangeable with a Roost-only checkout.
