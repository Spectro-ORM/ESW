# Spec: Deferred Features

**Status:** Proposed
**Date:** 2026-03-27
**Depends on:** ESW core (complete), Nexus integration (spec 01)

---

## 1. Overview

These are the features listed in ESW-SPEC §16 as deferred. This spec breaks
each one into a concrete design with scope, implementation approach, and
acceptance criteria.

---

## 2. Layout Helper — `conn.html(layout:content:)`

### 2.1 Purpose

Reduce boilerplate when wrapping a page body in a layout. Currently:

```swift
let body = _renderUserProfileBuffer(user: user)
return renderLayout(conn: conn, title: user.name, content: body)
```

With the helper:

```swift
return conn.html(layout: renderLayout, title: user.name) {
    _renderUserProfileBuffer(user: user)
}
```

### 2.2 Design

```swift
// Sources/Nexus/Connection+Layout.swift
extension Connection {
    public func html<each P>(
        layout: (Connection, repeat each P, String) -> Connection,
        _ params: repeat each P,
        content: () -> String
    ) -> Connection {
        let body = content()
        return layout(self, repeat each params, body)
    }
}
```

**Alternative (simpler, recommended for v0.1):**

Since layouts always take `title` + `content`, and the generated function
signature varies, a generic approach is complex. Instead, just provide a
convenience that makes the pattern slightly less verbose:

```swift
extension Connection {
    /// Renders a content block and wraps it in a layout.
    public func html(
        title: String,
        layout: (Connection, String, String) -> Connection,
        content: () -> String
    ) -> Connection {
        let body = content()
        return layout(self, title, body)
    }
}
```

Usage:
```swift
return conn.html(title: user.name, layout: renderLayout) {
    _renderUserProfileBuffer(user: user)
}
```

### 2.3 Tasks

| # | Task |
|---|------|
| 1 | Add `conn.html(title:layout:content:)` to `Connection` in `swift-nexus` |
| 2 | Add tests verifying the content block is called and passed to layout |
| 3 | Add a fixture template demonstrating the pattern |

### 2.4 Acceptance Criteria

- The helper compiles and runs.
- The layout receives the rendered content string.
- Content is not double-escaped (raw output is used for content injection).

---

## 3. Asset Path Helper — `assetPath()`

### 3.1 Purpose

Generate cache-busted URLs for static assets. Requires a manifest file
(e.g., `manifest.json`) mapping logical names to fingerprinted filenames.

### 3.2 Design

```swift
// Sources/ESW/AssetManifest.swift
public final class AssetManifest: Sendable {
    private let entries: [String: String]  // "app.css" → "app-abc123.css"

    public init(jsonPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        self.entries = try JSONDecoder().decode([String: String].self, from: data)
    }

    public func path(for name: String) -> String {
        entries[name] ?? name
    }
}
```

Templates use it via a global or passed-in manifest:

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
```

The `assetPath()` function needs to be available in the generated function's
scope. Options:

**Option A — Global function:**
```swift
// User provides in their app
func assetPath(_ name: String) -> String {
    AppManifest.shared.path(for: name)
}
```

**Option B — Parameter on assigns:**
```html
<%!
var manifest: AssetManifest
%>
<link href="<%= manifest.path(for: "app.css") %>">
```

**Recommendation:** Option A (global function) for simplicity. The ESW library
provides the `AssetManifest` type. The user wires it up as a global. No changes
to the template engine itself.

### 3.3 Tasks

| # | Task |
|---|------|
| 1 | Add `AssetManifest` type to `Sources/ESW/AssetManifest.swift` |
| 2 | Add tests for manifest loading and lookup |
| 3 | Document the global `assetPath()` pattern |
| 4 | Add fixture template using `assetPath()` |

### 3.4 Acceptance Criteria

- `AssetManifest` loads a JSON manifest and resolves asset paths.
- Missing assets fall back to the original name.
- Works with `<%= assetPath("...") %>` in templates.

---

## 4. Hot Reload in Development

### 4.1 Purpose

During development, automatically recompile `.esw` files when they change
without restarting `swift build`. This requires a file watcher.

### 4.2 Design

This is a **development workflow tool**, not a runtime feature. Two approaches:

**Option A — File watcher script (external):**

A shell script or Swift CLI that watches `.esw` files and runs
`ESWCompilerCLI` on change:

```bash
# dev_watch.sh
fswatch -o Sources/**/*.esw | while read; do
    swift build
done
```

**Option B — SwiftPM `prebuild` plugin:**

SPM prebuild plugins run before every build. Combined with `swift build
--build-system swiftpm`, this gives near-instant feedback. But SPM doesn't have
a watch mode — the developer still runs `swift build` manually.

**Option C — Standalone dev server with file watcher:**

A `swift-esw-dev` CLI that:
1. Watches `.esw` files using `DispatchSource.makeFileSystemObjectSource` or
   `FSEvents`.
2. On change, re-runs the tokenizer + code generator.
3. Copies the output to the build directory.
4. Optionally sends a WebSocket reload signal to the browser.

**Recommendation:** Start with Option A (external `fswatch` script) as
documented guidance. Option C is a nice-to-have for later.

### 4.3 Tasks

| # | Task |
|---|------|
| 1 | Document the `fswatch` + `swift build` workflow |
| 2 | Add a `scripts/dev_watch.sh` convenience script |
| 3 | (Future) Evaluate a standalone dev server with live reload |

### 4.4 Acceptance Criteria

- Developer can edit a `.esw` file and see the change reflected after the next
  build without manual intervention beyond the watcher running.

---

## 5. `conn.html(layout:content:)` — Extended Layout Composition

### 5.1 Purpose

Beyond the simple layout helper in §2, support **nested layouts** — e.g., an
admin layout that wraps an app layout.

### 5.2 Design

Since layouts are just functions that take a `content: String` parameter, nesting
is already possible:

```swift
let inner = _renderUserProfileBuffer(user: user)
let outer = _renderAdminLayoutBuffer(title: "Admin", content: inner)
return renderAppLayout(conn: conn, title: "App", content: outer)
```

No new API needed — this is a documentation and example task.

### 5.3 Tasks

| # | Task |
|---|------|
| 1 | Add a nested layout example to documentation |
| 2 | Add fixture templates demonstrating nested layouts |

---

## 6. Priority Order

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| 1 | Layout helper (`conn.html(layout:content:)`) | Small | High — reduces boilerplate in every route |
| 2 | Asset path helper (`AssetManifest`) | Small | Medium — needed for production CSS/JS |
| 3 | Hot reload | Medium | High — DX improvement, but external tools work |
| 4 | Nested layout docs | Tiny | Low — already works, just needs examples |

---

## 7. Explicitly Out of Scope

| Feature | Reason |
|---------|--------|
| Streaming templates | Buffer-then-flush is sufficient. Streaming adds complexity to `Connection` for marginal gain at v0.1 scale. |
| i18n / l10n helpers | Template engine should not own i18n. Users call translation functions in `<%= %>` tags. |
| Template caching | Moot — templates compile to native Swift functions. There is nothing to cache. |
| Custom escape functions | One escape function (`ESW.escape`) keeps the security model simple. Custom escaping invites XSS. |
