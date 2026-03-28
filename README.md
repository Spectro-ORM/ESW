# ESW — Embedded Swift Templates

A compile-time HTML template engine for Swift. Write `.esw` files with familiar ERB/EEx syntax, get type-safe Swift functions with zero runtime overhead.

```html
<!-- Views/donut_list.esw -->
<%!
var donuts: [Donut]
%>
<ul>
<% for donut in donuts { %>
  <li><%= donut.name %> — $<%= donut.price %></li>
<% } %>
</ul>
```

Use it directly in your route handler:

```swift
// Macro — returns String, framework-agnostic
return conn.html(#render("donut_list.esw"))

// Build plugin — generates a named function
return renderDonutList(conn: conn, donuts: donuts)
```

## Features

- **Just HTML.** No DSL. Designers can edit `.esw` files without knowing Swift.
- **Compile-time.** Templates become Swift code at build time. No runtime parsing, no file I/O per request.
- **Type-safe.** Template variables are Swift variables. Typos are compiler errors pointing at the `.esw` file.
- **XSS-safe by default.** `<%= %>` HTML-escapes. Raw output requires explicit `<%== %>`.
- **Two integration paths.** Swift macros (`#render`, `#esw`) for framework-agnostic use, or an SPM build plugin for auto-generated functions.

## Requirements

- Swift 6.3+
- macOS 14+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alembic-labs/swift-esw", from: "0.1.0"),
]
```

### Macro path (recommended)

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "ESW", package: "swift-esw"),
        ]
    ),
]
```

Build with `--disable-sandbox` to allow macro file reads:

```
swift build --disable-sandbox
```

### Build plugin path

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "ESW", package: "swift-esw"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "swift-esw"),
        ]
    ),
]
```

The build plugin auto-discovers `.esw` files and generates Swift functions. No `--disable-sandbox` needed.

## Tag Reference

| Tag | Name | Behavior |
|-----|------|----------|
| `<%= expr %>` | Output | Evaluates `expr`, HTML-escapes, writes to buffer |
| `<%== expr %>` | Raw output | Evaluates `expr`, writes **without** escaping |
| `<% code %>` | Execution | Runs Swift code, no output |
| `<%# comment %>` | Comment | Discarded entirely |
| `<%!-- comment --%>` | Multi-line comment | Discarded, can span lines and contain `%>` |
| `<%! ... %>` | Assigns | Front-matter declaring template parameters |
| `<%%` | Escape | Literal `<%` in output |
| `%%>` | Escape | Literal `%>` in output |

## Template Syntax

### Variables (assigns)

Declare template parameters in a front-matter block:

```html
<%!
var user: User
var posts: [Post]
var isAdmin: Bool = false
%>
<h1><%= user.name %></h1>
```

Default values are supported. If no front-matter is present, the template takes no parameters.

### Control flow

Standard Swift control flow, using `{` and `}` in execution tags:

```html
<% if user.isAdmin { %>
  <span class="badge">Admin</span>
<% } %>

<% for post in posts { %>
  <li><%= post.title %></li>
<% } %>

<% switch user.role { %>
<% case .admin: %>
  <span>Admin</span>
<% case .editor: %>
  <span>Editor</span>
<% default: %>
  <span>Viewer</span>
<% } %>
```

### Whitespace trimming

Control-only lines (execution tags as the sole content on a line) are trimmed by default — no blank lines in output:

```html
<ul>
<% for item in items { %>
  <li><%= item.name %></li>
<% } %>
</ul>
```

Renders cleanly as:

```html
<ul>
  <li>Chocolate</li>
  <li>Glazed</li>
</ul>
```

Force a blank line with `<%+`:

```html
<%+ someCode %>
```

## Using Macros

### `#render` — file-based templates

Reads a `.esw` file at compile time and expands to a `String`-returning closure. Template variables are captured from the surrounding scope:

```swift
let donuts = try await db.query(Donut.self).all()
return conn.html(#render("donut_list.esw"))
```

The file is resolved by walking up from the source file, checking `Views/<name>` and `<name>` directly at each level.

### `#esw` — inline templates

For small templates that don't need a separate file:

```swift
let badge = #esw("""
    <span class="badge"><%= count %></span>
    """)
```

Swift interpolation (`\(...)`) is rejected — use `<%= %>` instead.

### Framework-agnostic

Both macros return `String`. Wrap with whatever your framework provides:

```swift
// Nexus
conn.html(#render("page.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("page.esw"))))

// Vapor
Response(body: .init(string: #render("page.esw")))
```

## Using the Build Plugin

The build plugin generates named Swift functions from `.esw` files automatically:

| Filename | Generated function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(conn:...)` |
| `layout.esw` | `renderLayout(conn:...)` |
| `_user_card.esw` | `renderUserCard(conn:...)` + `_renderUserCardBuffer(...)` |

Partials (files starting with `_`) get both a `Connection`-returning function and a `String`-returning buffer variant for embedding in parent templates.

```swift
// Route handler
return renderUserProfile(conn: conn, user: user, posts: posts)

// Embedding a partial in a parent template
<%== _renderUserCardBuffer(user: user) %>
```

> **Note:** The build plugin generates code that imports `Nexus`. The macro path has no framework coupling.

## Layouts

A layout is just a template that accepts a `content` parameter:

```html
<!-- Views/layout.esw -->
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

Compose explicitly:

```swift
// With macros
let body = #render("user_profile.esw")
let page = #render("layout.esw")  // title and content captured from scope

// With build plugin
let body = _renderUserProfileBuffer(user: user)
return renderLayout(conn: conn, title: user.name, content: body)
```

## Escaping

`<%= %>` runs all output through `ESW.escape()`, which replaces `&`, `<`, `>`, `"`, and `'` with HTML entities. Numbers and booleans pass through unescaped.

To embed pre-rendered HTML without double-escaping, use `render()`:

```html
<%= render(_renderCardBuffer(user: user)) %>
```

Or use `<%== %>` for raw output:

```html
<%== _renderCardBuffer(user: user) %>
```

## Asset Fingerprinting

`AssetManifest` maps logical filenames to fingerprinted paths:

```swift
let manifest = try AssetManifest(jsonPath: "public/manifest.json")
func assetPath(_ name: String) -> String { manifest.path(for: name) }
```

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
<!-- renders: app-abc123.css -->
```

## Error Messages

Compiler errors point at the `.esw` file, not generated code:

```
Views/user_profile.esw:5:22: error: value of type 'User' has no member 'naem'
```

The `#render` macro gives clear diagnostics for common mistakes:

```
error: #render expects a file path (e.g. #render("template.esw")), not inline HTML.
       Use #esw("...") for inline templates.
```

## Architecture

```
swift-esw/
  Sources/
    ESW/                  Runtime library (escape, ESWValue, AssetManifest, macro declarations)
    ESWCompilerLib/       Tokenizer, code generator, whitespace trimmer (zero dependencies)
    ESWCompilerCLI/       CLI wrapper for build plugin
    ESWMacros/            Swift macro implementations (#render, #esw)
  Plugins/
    ESWBuildPlugin/       SPM build tool plugin
  Tests/                  130 tests across 10 suites
  Fixtures/
    PluginConsumer/       End-to-end integration test fixture
```

## Running Tests

```
swift test
```

To test the build plugin fixture end-to-end:

```
cd Fixtures/PluginConsumer && swift run App
```

## License

MIT
