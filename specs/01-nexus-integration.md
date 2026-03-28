# Spec: Nexus Integration

**Status:** Proposed
**Date:** 2026-03-27
**Depends on:** ESW core (complete)

---

## 1. Goal

Wire `swift-esw` into `swift-nexus` so that generated template functions compile
and run against a real `Connection`. After this work, a Nexus app can import
`ESW`, apply the `ESWBuildPlugin`, drop `.esw` files into its source target, and
call `renderFoo(conn:...)` from route handlers.

---

## 2. Scope

### 2.1 `conn.html()` on `Connection`

Add a single method to `Connection` (spec §11):

```swift
// Sources/Nexus/Connection+HTML.swift
extension Connection {
    public func html(
        _ body: String,
        status: HTTPResponse.Status = .ok
    ) -> Connection {
        var copy = self
        copy.response.status = status
        copy.response.headerFields[.contentType] = "text/html; charset=utf-8"
        copy.responseBody = .buffered(Data(body.utf8))
        copy.isHalted = true
        return copy
    }
}
```

Rules:
- Sets `Content-Type: text/html; charset=utf-8`.
- Defaults to HTTP 200, caller can override.
- Halts the connection (same semantics as `conn.json()`).
- Lives in `swift-nexus`, not `swift-esw`.

### 2.2 `swift-nexus` dependency update

`swift-nexus` adds `swift-esw` as a development dependency (for its own test
fixtures), **not** as a runtime dependency. The `ESW` runtime target has zero
dependencies — consuming apps import it directly.

### 2.3 Consumer-side wiring

A consuming app's `Package.swift`:

```swift
dependencies: [
    .package(url: "...", from: "0.1.0"),  // swift-nexus
    .package(url: "...", from: "0.1.0"),  // swift-esw
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "Nexus", package: "swift-nexus"),
            .product(name: "ESW",   package: "swift-esw"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "swift-esw"),
        ]
    ),
]
```

---

## 3. Tasks

| # | Task | Location |
|---|------|----------|
| 1 | Add `Connection.html(_:status:)` | `swift-nexus/Sources/Nexus/Connection+HTML.swift` |
| 2 | Add tests for `conn.html()` | `swift-nexus/Tests/NexusTests/ConnectionHTMLTests.swift` |
| 3 | Verify `Content-Type` header is set correctly | test |
| 4 | Verify `isHalted` is true after call | test |
| 5 | Verify status code defaults to 200, accepts override | test |
| 6 | Verify body round-trips through `responseBody` | test |

---

## 4. Verification

- `swift test` in `swift-nexus` passes all new `conn.html()` tests.
- Create a minimal Nexus app with one `.esw` file and one route — `swift build`
  succeeds, hitting the route returns the rendered HTML with correct headers.

---

## 5. Non-goals

- No changes to `swift-esw` itself.
- No layout helpers yet (see spec 04).
- No middleware or content negotiation.
