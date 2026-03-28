# ESW — Embedded Swift Templates
## Specification v0.1

**Status:** Proposed  
**Date:** 2026-03-27  
**Owner:** Alembic Labs  
**Repo:** `swift-esw` (standalone, consumed by `swift-nexus`)

---

## 1. Purpose

`.esw` (Embedded SWift) is a file-based HTML template engine for the Nexus
stack. It allows developers to write standard HTML files with embedded Swift
expressions, compiled at build time into native Swift functions via an SPM
Build Tool Plugin.

Design axioms:

1. **Just HTML.** No DSL to learn. No new API. A designer can touch `.esw`
   files without knowing Swift.
2. **Compile-time generation.** Templates are Swift functions after `swift
   build`. There is no runtime template parsing, no file I/O on request.
3. **Connection-native.** Generated functions take a `Connection` and return a
   `Connection`, exactly like every other Nexus handler.
4. **XSS-safe by default.** `<%= %>` always escapes. Raw output requires
   explicit opt-in via `<%== %>`.
5. **Zero new runtime dependencies.** The SPM plugin is a build tool. The
   generated code depends only on `Nexus` core, which the consuming app
   already imports.

---

## 2. File Format

Template files use the `.esw` extension and live inside Swift source targets,
colocated with the handlers that use them:

```
Sources/
  App/
    Routes/
      UserRoutes.swift
    Views/
      user_profile.esw
      layout.esw
      _user_card.esw        ← partial (leading underscore, convention only)
```

The SPM plugin discovers all `.esw` files within its target and processes them
before `swiftc` runs.

---

## 3. Tag Reference

Six tag types, consistent with ERB/EEx conventions.

| Tag | Name | Behaviour |
|-----|------|-----------|
| `<%= expr %>` | Output | Evaluates `expr`, HTML-escapes result, writes to buffer |
| `<%== expr %>` | Raw output | Evaluates `expr`, writes to buffer **without** escaping |
| `<% code %>` | Execution | Executes `code`, produces no output |
| `<%# comment %>` | Comment | Discarded entirely, produces no output, no Swift emitted |
| `<%%` | Escape open | Literal `<%` in output |
| `%%>` | Escape close | Literal `%>` in output |

### 3.1 Block tags

Control flow that opens a block uses `{` inside an execution tag. The closing
`}` uses its own execution tag. The Swift expression is emitted verbatim into
the generated function — the compiler validates it.

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

No special `<%{ %>` / `<%} %>` markers are required. The tokenizer emits
execution tags verbatim; Swift's own compiler validates brace balance. A
mismatched `{` or `}` is a **Swift compiler error**, not an ESW error — with
source maps pointing back to the `.esw` file.

### 3.2 Whitespace trimming

Control lines — execution tags (`<% %>`) that are the only non-whitespace
content on their line — are **trimmed by default**: the entire line (including
its trailing newline) is consumed and produces no output.

Output tags (`<%= %>`, `<%== %>`) are never trimmed. They render inline.

```html
<ul>
<% for item in items { %>    ← trimmed, no blank line
  <li><%= item.name %></li>  ← not trimmed, renders inline
<% } %>                      ← trimmed, no blank line
</ul>
```

Renders as:
```html
<ul>
  <li>Chocolate</li>
  <li>Glazed</li>
</ul>
```

To suppress trimming on a specific control line, append `-`:

```html
<% someCode -%>    ← explicit: trim trailing newline (same as default)
<% someCode %>     ← on a control-only line: trimmed by default
```

To **force** a blank line through from a control line (opt-in whitespace):

```html
<%+ someCode %>    ← preserve the trailing newline
```

---

## 4. Assigns — The Front Matter Block

Every `.esw` file that needs input data declares its parameters in a **front
matter block** at the top of the file:

```
<%!
var user: User
var posts: [Post]
var isAdmin: Bool = false
%>
```

Rules:

- Must be the first tag in the file if present.
- Contains valid Swift variable declarations — the plugin reads these to
  generate the function signature.
- Default values are supported (`var isAdmin: Bool = false`).
- If no front matter is present, the generated function takes only `conn:
  Connection`.

The generated function signature for the above:

```swift
func renderUserProfile(
    conn: Connection,
    user: User,
    posts: [Post],
    isAdmin: Bool = false
) -> Connection
```

---

## 5. Escaping

### 5.1 The ESWValue type

The runtime provides one type:

```swift
// Sources/ESW/ESWValue.swift
public enum ESWValue {
    case safe(String)    // already-escaped HTML, emitted by <%== %>
    case unsafe(String)  // user data, auto-escaped by <%= %>
}
```

`ESW.escape(_ value: Any?) -> String` is the function called for every `<%= %>`
output tag in the generated code:

```swift
public func escape(_ value: Any?) -> String {
    guard let value else { return "" }
    let string: String
    switch value {
    case let s as String:        string = s
    case let n as Int:           return String(n)     // numbers are always safe
    case let n as Double:        return String(n)     // numbers are always safe
    case let b as Bool:          return b ? "true" : "false"
    case let esw as ESWValue:
        switch esw {
        case .safe(let s):       return s             // already escaped
        case .unsafe(let s):     string = s
        }
    default:                     string = String(describing: value)
    }
    return string
        .replacingOccurrences(of: "&",  with: "&amp;")
        .replacingOccurrences(of: "<",  with: "&lt;")
        .replacingOccurrences(of: ">",  with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'",  with: "&#39;")
}
```

### 5.2 Tag escaping behaviour

```html
<%= user.name %>           → ESW.escape(user.name)        — safe
<%== someHTMLFragment %>   → _buf += someHTMLFragment     — raw, no escape
```

Numeric and boolean expressions are never HTML-escaped (they cannot contain
dangerous characters). Strings always go through `ESW.escape()`.

---

## 6. Token Types

The tokenizer produces a flat `[Token]` array. Six types:

```swift
enum Token {
    case text(String, metadata: Metadata)
    case output(String, metadata: Metadata)        // <%= %>
    case rawOutput(String, metadata: Metadata)     // <%== %>
    case code(String, metadata: Metadata)          // <% %>
    case comment(String, metadata: Metadata)       // <%# %>
    case assigns(String, metadata: Metadata)       // <%! %>
}

struct Metadata {
    let file: String      // original .esw path
    let line: Int
    let column: Int
}
```

`comment` tokens are dropped during code generation. `assigns` is only valid
as the first token; the code generator errors if it appears elsewhere.

---

## 7. Tokenizer Spec

The tokenizer is a linear scanner over the UTF-8 source. It does **not** parse
HTML — it is HTML-unaware. It scans for `<%` at the byte level.

### 7.1 Scanning rules

1. Accumulate bytes into a text buffer until `<%` is encountered.
2. On `<%`:
   - If next byte is `%`: emit a text token containing literal `<%`, advance
     past `%%`, continue scanning.
   - If next byte is `!`: read until `%>`, emit `.assigns`.
   - If next byte is `#`: read until `%>`, emit `.comment`.
   - If next byte is `=`:
     - If byte after `=` is `=`: read until `%>`, emit `.rawOutput`.
     - Otherwise: read until `%>`, emit `.output`.
   - Otherwise: read until `%>`, emit `.code`.
3. Flush the text buffer as a `.text` token before each non-text token.
4. On `%%>` inside a tag: treat as literal `%>` in the expression content.
5. Track line and column for every token's `Metadata`.

### 7.2 Whitespace trimming algorithm

Applied **after** tokenization as a post-processing pass:

```
for each .code token at index i:
    look at the .text token at i-1 (preceding text)
    if that text ends with optional spaces/tabs then a newline:
        trim those trailing whitespace chars + newline from the text token
    look at the .text token at i+1 (following text)
    if that text starts with optional spaces/tabs then a newline:
        trim those leading spaces/tabs + newline from the text token
```

"Control-only line" detection: a `.code` token is on a control-only line when
the preceding `.text` ends with `\n[spaces/tabs]` and the following `.text`
starts with `[spaces/tabs]\n` (or EOF). Both sides are trimmed.

### 7.3 Known caveat — `<%` inside attribute values

The tokenizer is HTML-unaware. `<%` inside an HTML attribute value string
will be interpreted as an opening tag delimiter:

```html
<!-- CAVEAT: this breaks the tokenizer -->
<div data-template="use <%= %> for output">
```

**Mitigation:** Use `<%%` to escape:

```html
<div data-template="use <%%= %%> for output">
```

This is the same behaviour as ERB and EEx. It is a known, documented
limitation, not a bug.

---

## 8. Code Generator

The code generator walks `[Token]` and emits a Swift source file.

### 8.1 Generated file structure

```swift
// AUTO-GENERATED by swift-esw. DO NOT EDIT.
// Source: Sources/App/Views/user_profile.esw

import Nexus

#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 1)
func renderUserProfile(
    conn: Connection,
    user: User,
    posts: [Post],
    isAdmin: Bool = false
) -> Connection {
    var _buf = ""
    // ... generated body ...
    return conn.html(_buf)
}
#sourceLocation()
```

### 8.2 Token → Swift emission

| Token | Emitted Swift |
|-------|--------------|
| `.text(s)` | `_buf += #"<escaped raw string>"#` |
| `.output(expr)` | `_buf += ESW.escape(\(expr))` |
| `.rawOutput(expr)` | `_buf += \(expr)` |
| `.code(s)` | `\(s)` (verbatim, on its own line) |
| `.comment` | nothing |
| `.assigns` | parsed into function parameters, not emitted as body |

Text tokens use Swift raw string literals (`#"..."#`) to avoid escaping
backslashes and quotes in HTML content.

### 8.3 Source location directives

Every emitted line includes a `#sourceLocation` directive so Swift compiler
errors point at the `.esw` file, not the generated `.swift` file:

```swift
func renderUserProfile(conn: Connection, user: User) -> Connection {
    var _buf = ""
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 3)
    _buf += #"<div class="profile"><h1>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 4)
    _buf += ESW.escape(user.name)
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 5)
    _buf += #"</h1>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 6)
    if user.isAdmin {
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 7)
    _buf += #"<span class="badge">Admin</span>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 8)
    }
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 9)
    return conn.html(_buf)
#sourceLocation()
}
```

A typo in `<%= user.naem %>` produces:

```
Sources/App/Views/user_profile.esw:4:22: error: value of type 'User' has no member 'naem'
```

Not a reference to a generated file. The developer sees the `.esw` line.

### 8.4 Function naming convention

Derived from the filename by stripping the `.esw` extension, converting
snake_case to camelCase, and prefixing with `render`:

| Filename | Generated function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(conn:...)` |
| `layout.esw` | `renderLayout(conn:...)` |
| `_user_card.esw` | `renderUserCard(conn:...)` |
| `index.esw` | `renderIndex(conn:...)` |

Leading underscores (partial convention) are stripped before camelCasing.

---

## 9. Partials

A partial is any `.esw` file. There is no special partial type. Since every
`.esw` file compiles to a Swift function, calling a partial is calling a
function:

```html
<%!
var users: [User]
%>
<ul>
<% for user in users { %>
  <%= renderUserCard(conn: conn, user: user).responseBodyString() %>
<% } %>
</ul>
```

**However**, this is awkward — it extracts the body from a `Connection` just
to embed it in a parent buffer. The better pattern is a **string-returning
variant** for partials.

The code generator detects partials (files with a leading `_`) and generates
two functions:

```swift
// Full Connection-returning variant (for use as a top-level handler)
func renderUserCard(conn: Connection, user: User) -> Connection {
    return conn.html(_renderUserCardBuffer(user: user))
}

// Buffer-returning variant (for embedding in parent templates)
func _renderUserCardBuffer(user: User) -> String {
    var _buf = ""
    // ... rendering ...
    return _buf
}
```

Usage in a parent template:

```html
<% for user in users { %>
  <%== _renderUserCardBuffer(user: user) %>
<% } %>
```

`<%==` (raw output) is correct here — the partial's output is already
HTML-escaped by the partial's own `<%= %>` tags.

---

## 10. Layouts

A layout is a `.esw` file that accepts a `content: String` parameter:

```html
<%!
var title: String
var content: String
%>
<!DOCTYPE html>
<html>
  <head>
    <title><%= title %></title>
  </head>
  <body>
    <%== content %>
  </body>
</html>
```

Usage in a route handler:

```swift
GET("/users/:id") { conn in
    let user = try await db.find(User.self, id: conn.params["id"])
    let body = _renderUserProfileBuffer(user: user)
    return renderLayout(conn: conn, title: user.name, content: body)
}
```

No magic. No implicit layout wrapping. Explicit composition — the same
philosophy as the rest of Nexus.

A `conn.html(layout:content:)` convenience helper can wrap this pattern later,
but the underlying mechanism is always just function calls.

---

## 11. `conn.html()` — Nexus Core Integration

One method added to `Connection`, mirroring `conn.json()`:

```swift
// Sources/Nexus/Connection+HTML.swift
extension Connection {

    /// Sets the response body to the given HTML string, sets
    /// `Content-Type: text/html; charset=utf-8`, and halts the connection.
    ///
    /// This is the integration point between .esw generated templates
    /// and the Nexus pipeline. Generated template functions call this
    /// method to produce their final Connection.
    ///
    /// - Parameters:
    ///   - body: The rendered HTML string.
    ///   - status: The HTTP response status. Defaults to `.ok`.
    /// - Returns: A halted connection with the HTML response body.
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

---

## 12. SPM Build Tool Plugin

### 12.1 Package structure

`swift-esw` is a standalone package with three targets:

```
swift-esw/
  Sources/
    ESW/                    ← runtime library (ESWValue, escape())
    ESWCompilerLib/         ← tokenizer + code generator (library, testable)
    ESWCompilerCLI/         ← thin CLI wrapper around ESWCompilerLib
  Plugins/
    ESWBuildPlugin/         ← SPM Build Tool Plugin
  Tests/
    ESWCompilerLibTests/
```

```swift
// Package.swift (swift-esw)
.plugin(
    name: "ESWBuildPlugin",
    capability: .buildTool(),
    dependencies: ["ESWCompilerCLI"]
),
.executableTarget(
    name: "ESWCompilerCLI",
    dependencies: ["ESWCompilerLib"]
),
.target(name: "ESWCompilerLib"),
.target(name: "ESW"),   // runtime, zero deps
```

### 12.2 Plugin behaviour

```swift
// Plugins/ESWBuildPlugin/ESWBuildPlugin.swift
struct ESWBuildPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }

        let eswFiles = target.sourceFiles
            .filter { $0.path.extension == "esw" }

        return eswFiles.map { file in
            let outputName = file.path.stem
                .snakeToCamel()
                .prefixed(with: "render_")
                + ".swift"
            let output = context.pluginWorkDirectory
                .appending(outputName)

            return .buildCommand(
                displayName: "Compiling \(file.path.lastComponent)",
                executable: try context.tool(named: "ESWCompilerCLI").path,
                arguments: [
                    file.path.string,
                    "--output", output.string,
                    "--source-location"
                ],
                inputFiles: [file.path],
                outputFiles: [output]
            )
        }
    }
}
```

One `buildCommand` per `.esw` file. SPM handles incremental builds — a
template is only recompiled when its source changes. The `--source-location`
flag enables `#sourceLocation` directives in the output.

### 12.3 Consumer integration

In the consuming app's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alembic-labs/swift-esw", from: "0.1.0"),
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "Nexus",  package: "swift-nexus"),
            .product(name: "ESW",    package: "swift-esw"),  // runtime only
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "swift-esw"),
        ]
    ),
]
```

The consumer imports `ESW` for the runtime (`ESW.escape`). The plugin is
invisible at runtime — it only participates in the build.

---

## 13. Error Handling

### 13.1 Tokenizer errors

The tokenizer can produce one error:

```swift
enum ESWTokenizerError: Error {
    case unterminatedTag(file: String, line: Int, column: Int)
}
```

An unterminated `<%` (no closing `%>`) before EOF. The CLI tool prints:

```
Sources/App/Views/user_profile.esw:12:4: error: unterminated ESW tag
```

### 13.2 Assigns errors

```swift
enum ESWAssignsError: Error {
    case assignsNotFirst(file: String, line: Int)   // <%! %> appeared after content
    case invalidDeclaration(file: String, line: Int, text: String)
}
```

### 13.3 Swift compiler errors

All other errors (type errors, missing variables, undefined functions) are
Swift compiler errors, reported against the `.esw` file via
`#sourceLocation`. No special handling needed.

---

## 14. Tokenizer Test Spec

These are the cases the tokenizer must pass before the code generator is
written.

```swift
// ESWCompilerLibTests/TokenizerTests.swift

// Pure text
tokenize("hello world")
// → [.text("hello world", line:1)]

// Output tag
tokenize("<%= user.name %>")
// → [.output("user.name", line:1)]

// Raw output tag
tokenize("<%== rawHTML %>")
// → [.rawOutput("rawHTML", line:1)]

// Execution tag
tokenize("<% if x { %>")
// → [.code("if x {", line:1)]

// Comment tag — discarded
tokenize("<%# this is a comment %>")
// → [.comment("this is a comment", line:1)]

// Assigns block
tokenize("<%!\nvar user: User\n%>")
// → [.assigns("var user: User", line:1)]

// Delimiter escape
tokenize("show <%% tag %%>")
// → [.text("show <% tag %>", line:1)]

// Mixed content
tokenize("<h1><%= title %></h1>")
// → [.text("<h1>", line:1), .output("title", line:1), .text("</h1>", line:1)]

// Multiline — line tracking
tokenize("<p>\n<%= name %>\n</p>")
// → [.text("<p>\n", line:1), .output("name", line:2), .text("\n</p>", line:2)]

// Whitespace trimming — control-only line
tokenize("<% if x { %>\nhello\n<% } %>")
// → [.code("if x {", line:1), .text("hello\n", line:2), .code("}", line:3)]
// note: leading \n after first tag trimmed, trailing \n before last tag trimmed

// Unterminated tag — error
tokenize("<% oops")
// → throws ESWTokenizerError.unterminatedTag(line:1, column:1)

// Assigns not first — error
tokenize("<p>hello</p>\n<%!\nvar x: Int\n%>")
// → throws ESWAssignsError.assignsNotFirst(line:2)
```

---

## 15. Full Example

### Source: `Sources/App/Views/user_profile.esw`

```html
<%!
var user: User
var posts: [Post]
%>
<div class="profile">
  <h1><%= user.name %></h1>
  <p class="email"><%= user.email %></p>
  <% if user.isAdmin { %>
    <span class="badge">Admin</span>
  <% } %>
  <ul class="posts">
    <% for post in posts { %>
      <li>
        <a href="/posts/<%= post.id %>"><%= post.title %></a>
      </li>
    <% } %>
  </ul>
</div>
```

### Generated: `(build dir)/render_user_profile.swift`

```swift
// AUTO-GENERATED by swift-esw. DO NOT EDIT.
// Source: Sources/App/Views/user_profile.esw

import Nexus
import ESW

func renderUserProfile(
    conn: Connection,
    user: User,
    posts: [Post]
) -> Connection {
    var _buf = ""
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 4)
    _buf += #"<div class="profile">"#
    _buf += #"<h1>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 5)
    _buf += ESW.escape(user.name)
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 5)
    _buf += #"</h1>"#
    _buf += #"<p class="email">"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 6)
    _buf += ESW.escape(user.email)
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 6)
    _buf += #"</p>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 7)
    if user.isAdmin {
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 8)
    _buf += #"<span class="badge">Admin</span>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 9)
    }
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 10)
    _buf += #"<ul class="posts">"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 11)
    for post in posts {
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 12)
    _buf += #"<li><a href="/posts/"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 12)
    _buf += ESW.escape(post.id)
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 12)
    _buf += #"">"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 13)
    _buf += ESW.escape(post.title)
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 13)
    _buf += #"</a></li>"#
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 14)
    }
#sourceLocation(file: "Sources/App/Views/user_profile.esw", line: 15)
    _buf += #"</ul></div>"#
#sourceLocation()
    return conn.html(_buf)
}
```

### Route handler

```swift
GET("/users/:id") { conn in
    guard let user = try await db.repo().query(User.self)
        .where { $0.id == conn.params["id"] }
        .first()
    else {
        throw NexusHTTPError(.notFound, message: "User not found")
    }
    let posts = try await db.repo().query(Post.self)
        .where { $0.authorId == user.id }
        .orderBy(\.createdAt, .desc)
        .limit(10)
        .all()
    return renderUserProfile(conn: conn, user: user, posts: posts)
}
```

---

## 16. What This Spec Does NOT Cover (Deferred)

| Feature | Notes |
|---------|-------|
| Asset path helper (`assetPath()`) | Requires `Plug.Static` + manifest. Sprint 8. |
| Layout helper (`conn.html(layout:content:)`) | Convenience wrapper. Trivial post-MVP. |
| Streaming templates | Buffer-then-flush is sufficient for v0.1. |
| i18n / l10n helpers | Out of scope for template engine. |
| Hot reload in development | Requires file watcher. Post-MVP. |
| Template caching | Moot — templates are compiled, not interpreted. |
| Custom escape functions | `ESW.escape()` is the one escape. No per-template overrides. |

---

## 17. Dependency Summary

| Package | Role | Dependency type |
|---------|------|----------------|
| `swift-esw` (ESW target) | Runtime: `ESWValue`, `ESW.escape()` | Library dep in consuming app |
| `swift-esw` (ESWBuildPlugin) | Build tool: `.esw` → `.swift` | Plugin dep in consuming app |
| `swift-nexus` (Nexus target) | `Connection`, `conn.html()` | Library dep in consuming app |

`swift-esw` has zero runtime dependencies of its own. The `ESW` library target
is pure Swift, no Foundation import.
