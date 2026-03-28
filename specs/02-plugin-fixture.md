# Spec: End-to-End Plugin Test Fixture

**Status:** Proposed
**Date:** 2026-03-27
**Depends on:** ESW core (complete), Nexus integration (spec 01)

---

## 1. Goal

Validate that the SPM Build Tool Plugin works end-to-end in a real consumer
package: `.esw` files are discovered, compiled to `.swift`, and the generated
functions are callable from Swift code. This catches issues that unit tests on
the compiler library alone cannot — plugin discovery, file I/O, incremental
builds, `#sourceLocation` correctness, and import resolution.

---

## 2. Fixture Package Structure

A self-contained test package inside this repo:

```
Fixtures/
  PluginConsumer/
    Package.swift
    Sources/
      App/
        main.swift
        Views/
          hello.esw
          _greeting.esw
          layout.esw
```

### 2.1 `Package.swift`

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PluginConsumer",
    dependencies: [
        .package(path: "../../"),  // swift-esw (local)
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "ESW", package: "swift-esw"),
            ],
            plugins: [
                .plugin(name: "ESWBuildPlugin", package: "swift-esw"),
            ]
        ),
    ]
)
```

### 2.2 Template files

**`hello.esw`** — simple output, no assigns:
```html
<h1>Hello, World!</h1>
```

**`_greeting.esw`** — partial with assigns:
```html
<%!
var name: String
var greeting: String = "Hello"
%>
<p><%= greeting %>, <%= name %>!</p>
```

**`layout.esw`** — layout pattern with raw content:
```html
<%!
var title: String
var content: String
%>
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%== content %></body>
</html>
```

### 2.3 `main.swift`

```swift
import ESW

// Verify generated functions exist and are callable.
// We can't call conn.html() without Nexus, so just test the buffer variants
// and verify the render functions are generated.

// Partial generates buffer function
let greeting = _renderGreetingBuffer(name: "World")
assert(greeting.contains("Hello"))
assert(greeting.contains("World"))

// Default parameter works
let custom = _renderGreetingBuffer(name: "Swift", greeting: "Howdy")
assert(custom.contains("Howdy"))

// Escaping works
let xss = _renderGreetingBuffer(name: "<script>alert('xss')</script>")
assert(!xss.contains("<script>"))
assert(xss.contains("&lt;script&gt;"))

print("All fixture assertions passed.")
```

---

## 3. Tasks

| # | Task |
|---|------|
| 1 | Create `Fixtures/PluginConsumer/` directory and `Package.swift` |
| 2 | Create the three `.esw` template files |
| 3 | Create `main.swift` with compile-time and runtime assertions |
| 4 | Run `swift build` in the fixture directory — must succeed |
| 5 | Run the built executable — all assertions must pass |
| 6 | Verify `#sourceLocation` directives: introduce a deliberate typo in a `.esw` file, confirm the compiler error points to the `.esw` file and line, not the generated `.swift` file |
| 7 | Verify incremental builds: touch one `.esw` file, rebuild, confirm only that file is recompiled |

---

## 4. CI Integration

Add a step to CI (when CI exists) that:

```bash
cd Fixtures/PluginConsumer
swift build
swift run App
```

This ensures the plugin contract doesn't break across releases.

---

## 5. Edge Cases to Cover

| Case | Template |
|------|----------|
| Empty file (no tags, no assigns) | `empty.esw` containing just `<p>static</p>` |
| All tag types in one file | `kitchen_sink.esw` with `<%= %>`, `<%== %>`, `<% %>`, `<%# %>`, `<%! %>`, `<%%`, `%%>` |
| Deeply nested control flow | `nested.esw` with `if` inside `for` inside `if` |
| Unicode content | `unicode.esw` with emoji and CJK characters in text and assigns |
| Multiline expressions | `<%= users\n  .filter { $0.active }\n  .count %>` |

---

## 6. Non-goals

- No HTTP server in the fixture — just compile and assert.
- No performance benchmarking.
- No testing of hot reload (deferred feature).
