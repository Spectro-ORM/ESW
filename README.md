# ESW

**Peregrine’s HTML template engine: editable HTML, compiled Swift expressions, and typed components.**

---

## Why ESW?

Write templates in familiar HTML syntax, compile them to Swift code at build time.

`Views/users.esw`:

```html
<%!
var users: [User]
%>
<ul>
<% for user in users { %>
  <li><%= user.name %> — <%= user.email %></li>
<% } %>
</ul>
```

**Generates:**

```swift
func renderUsers(users: [User]) -> String {
    var _buf = ESWBuffer()
    _buf.append("<ul>")
    for user in users {
        _buf.append("<li>")
        _buf.appendEscaped(user.name)
        _buf.append(" — ")
        _buf.appendEscaped(user.email)
        _buf.append("</li>")
    }
    _buf.append("</ul>")
    return _buf.finalize()
}
```

**Benefits:**
- **No runtime template parsing** — Templates become Swift code during the build.
- **Type-safe** — Template variables are Swift variables. Typos are compiler errors.
- **HTML escaping by default** — Dynamic text and attributes are escaped. Trusted HTML requires explicit opt-in.
- **HTML authoring** — Use familiar HTML with Swift expressions, components, and slots.

---

## Quick Start

### Installation

These APIs are under development in this checkout. For a Peregrine app using this implementation, add a local dependency to `Package.swift`:

```swift
dependencies: [
    .package(path: "../esw"),
]
```

### Choose Your Integration

### Option A: Build Plugin (Recommended for Peregrine)

The plugin compiles `.esw` and `.heex` files into `String`-returning functions. Template files are explicit build inputs, so editing a template rebuilds its renderer.

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "ESW", package: "esw"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "esw"),
        ]
    ),
]
```

In a Peregrine route, use `conn.html(renderUsersIndex(users: users))`. The renderer returns ordinary HTML; the framework owns the response.

### Option B: Macros

Add the `ESW` product to your target for inline `#esw` and `#heex` templates. They capture Swift values from the surrounding scope. The `#render` file macro is also available, but its file read does not itself establish a SwiftPM template dependency; prefer the plugin for file templates that must rebuild reliably.

File macros require compile-time file access:

```bash
swift build --disable-sandbox
```

### Your First Template

Create `Views/greeting.esw`:

```html
<%!
var name: String
%>
<h1>Hello, <%= name %>!</h1>
```

**Use with macros (framework-agnostic):**

```swift
import ESW

func greet(name: String) -> String {
    return #render("greeting.esw")
}
```

Wrap the result with whatever your framework provides:

```swift
// Nexus
conn.html(#render("greeting.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("greeting.esw"))))

// Vapor
Response(body: .init(string: #render("greeting.esw")))
```

**Or with the build plugin:**

```swift
return conn.html(renderGreeting(name: "World"))
```

---

## Syntax Reference

| Tag | Purpose | Example |
|-----|---------|---------|
| `<%= expr %>` | Output (HTML-escaped) | `<%= user.name %>` |
| `<%== expr %>` | Raw output (no escaping) | `<%== rawHTML %>` |
| `<% code %>` | Swift code | `<% if condition { %>` |
| `<%# comment %>` | Comment | `<%# This is a comment %>` |
| `<%!-- comment --%>` | Multi-line comment | `<%!-- Across\nlines --%>` |
| `<%%` | Literal `<%` | `<%%` renders as `<%` |
| `%%>` | Literal `%>` | `%%>` renders as `%>` |
| `<%! vars %>` | Template parameters | See below |
| `<.component />` | Component tag | See below |
| `<:slot></:slot>` | Named slot | See below |

### HTML-Aware Templates (`.heex`)

Use `.heex` files or the `#heex` macro for balanced HTML tags, brace interpolation, dynamic attributes, and directives. Expressions are Swift:

```html
<%!
var items: [String]
var show: Bool = true
%>
<section :if={show} class={["items", items.isEmpty ? "empty" : nil]}>
  <ul>
    <li :for={item in items}>{item}</li>
  </ul>
</section>
```

| Syntax | Behavior |
|--------|----------|
| `{expression}` | HTML-escaped body output, like `<%= expression %>` |
| `title={value}` | Quoted, escaped attribute; `nil` omits it |
| `disabled={flag}` | Boolean attribute: `true` emits it, `false` omits it |
| `aria-expanded={flag}` | `aria-*` and `data-*` booleans render as `"true"` or `"false"` |
| `class={["button", active ? "active" : nil]}` | Joins class names; ignores `nil`, booleans, and empty entries |
| `{attributes}` inside a tag | Expands a `[String: Any?]` map in sorted key order |
| `:if={condition}` | Conditionally renders an element or component |
| `:for={item in items}` | Repeats an element or component |

When both directives appear, `:for` creates the scope for `:if`, regardless of their attribute order:

```html
<li :if={item.count > 0} :for={item in items}>{item.name}</li>
```

The existing `<% ... %>` tags, components, and string slots also work in HEEx mode. Use `title={expression}` for dynamic HTML attributes; embedded `<%= ... %>` inside a quoted attribute is rejected. Attribute values are always escaped, including values marked with `render(...)`.

HTML mode reports unclosed or mismatched tags, duplicate attributes, and malformed directives with source locations. Non-void elements need closing tags or `/>`. HTML comments and the bodies of `<script>` and `<style>` keep braces literal while still evaluating `<% ... %>` tags and processing escaped EEx delimiters. A bare `phx-no-curly-interpolation` attribute applies that brace rule to an HTML element, component, or slot body and its descendants; dynamic attributes and EEx tags still work, and the control attribute is removed from the output. Use `\{` and `\}` for literal braces in body text (in a Swift literal, use a raw string or escape the backslash).

`.esw` files retain their text-template behavior: literal braces and HTML fragments are allowed. HEEx mode is a Swift template syntax inspired by Phoenix; it does not include LiveView state, diffing, or events.

### Template Parameters

Declare typed Swift `var` or `let` parameters in a front-matter block. SwiftParser handles multiline defaults and closure types. Add explicit imports for types from other modules:

```html
<%!
import Peregrine
var user: User
var posts: [Post]
var isAdmin: Bool = false
%>
<h1><%= user.name %></h1>
<% if isAdmin { %>
  <span class="badge">Admin</span>
<% } %>
```

Imports belong to the generated Swift file. Inline macros use imports from their enclosing Swift source. Older templates declaring exactly `Connection` without any explicit import retain the Nexus import for compatibility; other type names do not cause inferred imports.

### Control Flow

Standard Swift control structures:

```html
<% if user.isLoggedIn { %>
  <p>Welcome back!</p>
<% } %>

<% for post in posts { %>
  <article><%= post.title %></article>
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

### Whitespace

Control-only lines are automatically trimmed (no blank lines in output):

```html
<ul>
<% for item in items { %>
  <li><%= item.name %></li>
<% } %>
</ul>
```

Renders as:
```html
<ul>
  <li>Apple</li>
  <li>Orange</li>
</ul>
```

Force a blank line with `<%+`:

```html
<%+ someCode %>
```

---

## Component Tags

Build reusable UI components with self-closing tags.

### Basic Components

```swift
// App/Components/Button.swift
struct Button: ESWComponent {
    static func render(label: String, disabled: Bool = false) -> String {
        """
        <button\(disabled ? " disabled" : "")>\(ESW.escape(label))</button>
        """
    }
}
```

**Usage:**

```html
<.button label="Click me" />
<.button label={item.name} disabled />
```

Generates:

```swift
Button.render(label: "Click me", disabled: true)
```

### Component Slots

Pass content regions to components using slots:

```swift
struct Card: ESWComponent {
    static func render(
        title: String,
        footer: String = "",       // Named slots in alphabetical order
        header: String = "",
        content: String = ""       // Default slot
    ) -> String {
        """
        <div class="card">
            <h2>\(ESW.escape(title))</h2>
            \(header)
            <div class="body">\(content)</div>
            \(footer)
        </div>
        """
    }
}
```

**Usage:**

```html
<.card title="User Profile">
  <:header>
    <h1><%= user.name %></h1>
    <small><%= user.title %></small>
  </:header>
  <p><%= user.bio %></p>
  <:footer>
    <small>Last updated: <%= user.updatedAt %></small>
  </:footer>
</.card>
```

**Slot rules:**

- Content outside named slots goes to the default `content:` parameter.
- `<:name>` regions map to named parameters and must be direct component children in HTML mode.
- Attributes follow source order; named slots follow alphabetical order, with `content:` last. Match that order in your Swift signature.
- A single named slot without attributes or directives remains a `String`, preserving existing components.

### Typed, Deferred Slots

Use repeated entries, slot attributes, or `:let` to pass an ordered array of `ESWSlot<Attributes, Input>`. Swift checks both the attributes and the input supplied by the component:

```swift
struct Person { let name: String }
struct ColumnAttributes { let label: String }

enum UI {
    static func table(people: [Person], column: [ESWSlot<ColumnAttributes, Person>]) -> String {
        let header = column.map { "<th>\(ESW.escape($0.attributes.label))</th>" }.joined()
        let rows = people.map { person in
            "<tr>" + column.map { "<td>\($0.render(person))</td>" }.joined() + "</tr>"
        }.joined()
        return "<table><thead>\(header)</thead><tbody>\(rows)</tbody></table>"
    }
}
```

```html
<UI.table people={people}>
  <:column label="Name" :let={person}><b>{person.name}</b></:column>
  <:column label="Details" :if={showDetails} :let={person}>{person.name}</:column>
</UI.table>
```

`<UI.table>` calls the qualified Swift function directly. `<.person-table>` continues to call `PersonTable.render`.

Slot attributes are evaluated at the call site. The body runs only when the component calls `entry.render(input)`, and may run once per row or not at all. Within a template, `{renderSlot(entry, input)}` embeds the rendered body without double escaping. `renderSlot(entries, input)` renders a collection in order. Use `ESWEmptySlotAttributes` for entries without attributes and `Void` for bodies without input; `renderSlot(entries)` handles the latter.

`:for` can create entries and `:if` can filter them. The loop variable is available to attributes, conditions, and content. The `:let` binding belongs only to the deferred body; it is unavailable to that entry’s attributes or condition. Tuple patterns such as `:let={(key, value)}` are supported. A self-closing entry cannot declare `:let`.

A component can make a slot optional by giving its array parameter a default of `[]`. Missing required parameters, wrong attribute types, and unknown input members are Swift compilation errors.

### Deferred Default Content

`:let` on a component supplies a Swift closure as its default `content` argument:

```swift
struct FormContext { let fieldName: String; let value: String }

struct Form: ESWComponent {
    static func render(value: String, content: (FormContext) -> String) -> String {
        "<form>" + content(FormContext(fieldName: "name", value: value)) + "</form>"
    }
}
```

```html
<.form value={name} :let={form}>
  <input name={form.fieldName} value={form.value} />
</.form>
```

Named slots retain their own scope; a default slot’s binding does not leak into them. Components without `:let` retain their existing String content parameter.

---

## Macros

ESW provides three Swift macros for template rendering.

### `#render` — File Templates

Reads a `.esw` or `.heex` file at compile time and expands to a `String`-returning closure. The extension selects the syntax:

```swift
let users = try await db.query(User.self).all()
let html = #render("users.esw")
```

Template variables are captured from the surrounding scope. Front-matter defaults apply to generated functions; macros require the referenced variables in scope, including those with defaults.

Wrap with your framework:

```swift
// Nexus
conn.html(#render("users.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("users.esw"))))

// Vapor
Response(body: .init(string: #render("users.esw")))
```

**File resolution:** Searches `Views/<name>` and `<name>` up to 6 directory levels up.

### `#esw` — Inline Templates

For small templates:

```swift
let badge = #esw("""
    <span class="badge"><%= count %></span>
    """)
```

### `#heex` — Inline HTML-Aware Templates

```swift
let items = ["Swift", "HTML"]
let html = #heex("""
    <ul><li :for={item in items}>{item}</li></ul>
    """)
```

Inline macros decode normal and raw Swift string literals. Use template expressions for dynamic content; Swift string interpolation inside the template literal is rejected.

### Framework Integration

The macro returns `String` — wrap it with whatever your framework provides:

```swift
// Nexus
conn.html(#render("page.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("page.esw"))))

// Vapor
Response(body: .init(string: #render("page.esw")))
```

**Note:** File templates via `#render` require `--disable-sandbox` for compile-time file reads. `#esw` and `#heex` do not read template files.

---

## Build Plugin

Auto-generates Swift functions returning `String` from `.esw` and `.heex` files.

### Generated Functions

| Filename | Generated Function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(...)` |
| `layout.esw` | `renderLayout(...)` |
| `tasks.heex` | `renderTasks(...)` |
| `users/index.heex` | `renderUsersIndex(...)` |
| `posts/index.esw` | `renderPostsIndex(...)` |
| `users/_card.heex` | `renderUsersCard(...)` + `_renderUsersCardBuffer(...)` |
| `_user_card.esw` | `renderUserCard(...)` + `_renderUserCardBuffer(...)` |

### Usage

```swift
return conn.html(renderUserProfile(user: user, posts: posts))
```

**Partials** (files starting with `_`) also get a `_render…Buffer(...)` alias returning the same `String`. Both variants retain parameter defaults.

Names are relative to `Views/` (or the target directory for templates outside it). Directory names are part of the function name, so separate resources can each have `index.heex`. Underscores and hyphens separate words in generated names. The plugin rejects filename collisions such as `user_card.esw` and `user-card.heex`, which both generate `renderUserCard`.

### Compiler CLI

```bash
swift run ESWCompilerCLI Views/tasks.heex --output /tmp/renderTasks.swift --source-location
```

Use `--heex` to opt into HTML mode for a file with a different extension. A batch uses the same naming and collision checks as the plugin:

```bash
swift run ESWCompilerCLI --batch --root Sources/App --output /tmp/ESWTemplates.swift Sources/App/Views/users/index.heex Sources/App/Views/posts/index.esw
```

The plugin regenerates one Swift file for the target when a template changes. Generation is atomic: parsing or name-collision errors leave the previous output intact.

---

## Layouts

Wrap page content in a consistent layout shell.

### Layout Template

`Views/layout.esw`:

```html
<%!
var title: String
var content: String
%>
<!DOCTYPE html>
<html>
  <head>
    <title><%= title %></title>
    <link rel="stylesheet" href="/app.css">
  </head>
  <body>
    <%== content %>
  </body>
</html>
```

### Composition

```swift
let content = #render("user_profile.esw")
let title = "User profile"
let page = #render("layout.esw")

// Wrap with your framework (Nexus example)
conn.html(page)
```

---

## Escaping

- `<%= %>` — HTML-escapes output (default)
- `<%== %>` — Raw output, no escaping

Escaping processes Unicode scalars, including quotes with combining marks. Trusted body HTML is still escaped in attribute values. HTML escaping does not serialize JavaScript/CSS data or validate URL schemes; prepare values for those contexts explicitly.

To embed pre-rendered HTML without double-escaping:

```html
<%= render(_renderCardBuffer(user: user)) %>
```

Or use raw output:

```html
<%== _renderCardBuffer(user: user) %>
```

---

## Asset Fingerprinting

Cache-bust static assets using `AssetManifest`.

### Create a Manifest

Build tools generate a mapping:

```json
{
  "app.css": "app-abc123.css",
  "app.js": "app-def456.js"
}
```

### Use in Templates

```swift
import ESW

let manifest = try AssetManifest(jsonPath: "public/manifest.json")

func assetPath(_ name: String) -> String {
    manifest.path(for: name)
}
```

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
<script src="<%= assetPath("app.js") %>"></script>
```

**Fallback:** Missing assets return the original name.

---

## Hot Reload

Auto-recompile `.esw` and `.heex` files during development.

### Setup

Install fswatch 1.22 or newer:

```bash
brew install fswatch
```

### Run the Watch Script

```bash
./scripts/dev_watch.sh
```

Watches `.esw` and `.heex` files outside `.build` and `.git`, and runs `swift build` on changes.

---

## Error Messages

Generated function errors point to the template file:

```
Views/user_profile.esw:5:22: error: value of type 'User' has no member 'naem'
```

The macro also provides clear diagnostics:

```
error: #render expects a file path (e.g. #render("template.esw")), not inline HTML.
       Use #esw("...") for inline templates.
```

---

## Development

### Run Tests

```bash
swift test
```

### Test Build Plugin Fixture

```bash
cd Fixtures/PluginConsumer
swift run --disable-sandbox App
```

### Integration and Peregrine Generator Checks

```bash
python3 scripts/check_integration.py --peregrine ../Peregrine
```

This verifies consumer rendering, a template-only incremental rebuild, failed-batch output preservation, and negative Swift type checks for slots. With `--peregrine`, it also compiles Peregrine’s generator sources, feeds the resulting templates through ESW, parses generated Swift routes, and evaluates generated package manifests. It does not run the generated application’s database or HTTP stack.

### Hot Reload Development

```bash
# Terminal 1: Watch ESW and HEEx files
./scripts/dev_watch.sh

# Terminal 2: Run your app
swift run App
```

---

## Architecture

```
swift-esw/
├── Sources/
│   ├── ESW/                  # Runtime library
│   │   ├── ESWBuffer.swift    # String builder
│   │   ├── ESWComponent.swift # Component protocol
│   │   ├── Attributes.swift   # Dynamic HTML attributes
│   │   ├── Slots.swift        # Typed deferred slot entries
│   │   ├── AssetManifest.swift
│   │   └── Macros.swift       # Macro declarations
│   ├── ESWCompilerLib/       # Compiler core
│   │   ├── Tokenizer.swift    # Lexical analysis
│   │   ├── HTMLTokenizer.swift # HTML validation and directives
│   │   ├── SwiftLexicalScanner.swift # Swift strings and comments
│   │   ├── ComponentResolver.swift  # Component tree building
│   │   ├── CodeGenerator.swift       # Swift code generation
│   │   └── Compiler.swift
│   ├── ESWMacros/            # Macro implementations
│   └── ESWCompilerCLI/       # Standalone CLI
├── Plugins/ESWBuildPlugin/   # SPM plugin
├── Tests/                    # Compiler and runtime tests
└── Fixtures/                  # Integration test app
```

### Compiler Pipeline

```
.esw / .heex source
    ↓
Tokenizer (text or HTML mode) → Tokens
    ↓
WhitespaceTrimmer → Trimmed tokens
    ↓
AssignsParser → Parameters
    ↓
ComponentResolver → RenderNode tree
    ↓
CodeGenerator → Swift code
```

---

## Requirements

- Swift 6.3+
- macOS 14+

---

## License

MIT

## Design and Compatibility

See [the engine design](Documentation/TemplateEngine.md) for implementation boundaries and [the EEx/HEEx comparison](Documentation/HEExParity.md) for primary-source research. ESW uses Swift expressions and returns complete HTML strings. LiveView-style diffs, event transport, asynchronous rendering, and editor formatting are separate work. No comparative performance claim is made.
