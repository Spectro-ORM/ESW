# ESW

**HTML templates for Swift: editable HTML, compiled expressions, typed components, and live rendering.**

## Library documentation

Browse the [documentation for the latest release](https://roost-framework.github.io/ESW/docs/latest/),
or [pick a release](https://roost-framework.github.io/ESW/docs/). Each release has its
own guides and API references for `ESW`, `ESWLive`, and `ESWCompilerLib`. The
[library documentation index](Documentation/README.md) lists the guides in this
checkout. Build a browsable DocC site for the current checkout with:

```sh
python3 scripts/build_docs.py
```

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

## Feature Coverage: EEx, HEEx, and LiveView

ESW covers everyday EEx-style templates and HEEx-style HTML authoring with Swift
expressions. `ESWLive` adds a smaller live runtime. These are separate layers:
`.esw` corresponds to EEx, HESW (HTML-aware ESW, `.hesw`) to HEEx authoring, and
`ESWLive` plus an HTTP adapter to Phoenix LiveView. Templates and browser
protocols are not interchangeable with Phoenix.

| Template capability | ESW support |
| --- | --- |
| Expressions, conditions, loops, escaped output and explicit raw HTML | Implemented with Swift |
| Compile templates into functions | Build plugin and macros |
| Separate view logic and template | `@ESWTemplate` on ordinary Swift structs; no template header required |
| HTML validation, dynamic/boolean attributes, class lists and attribute spreads | Implemented in HESW |
| `:if` / `:for`, function components, default/named/repeated/bound slots | Implemented; arguments follow Swift ordering and type checking |
| Keyed comprehensions with `:key` | Implemented on HTML elements and function components with `:for`; nested lists supported |
| Editor tooling | Neovim syntax highlighting; dedicated template formatter and LSP missing |
| EEx runtime evaluation and customizable engine API | No equivalent public API |

| Live capability | ESWLive support |
| --- | --- |
| Initial server rendering, server-owned state, serialized async event handling | Implemented |
| Browser transport | SSE updates and POST events; its own protocol |
| Click, submit, change and debounce bindings | Implemented basic bindings |
| Focus, selection, dirty-input preservation, reconnect and event retries | Implemented |
| Incremental rendering | Changed dynamic values and keyed row patches; every Swift expression still evaluates |
| Assign dependency tracking and general component render trees | Missing; string-returning components remain opaque fragments |
| Nested stateful live components, streams and live navigation | Missing |
| Integrated live uploads, Phoenix-style JS hooks/commands and managed async assignments | Missing |

Roost owns HTTP conveniences: `conn.render` supplies form context and layout,
and `<.form>` handles CSRF and method overrides. Field binding and nested forms
equivalent to Phoenix's `to_form` / `inputs_for` remain missing. The Roost live
adapter currently lives in Roost Playground; this repository's development
adapter retains the old Peregrine API, and the ordinary/live Roost rendering
paths still need consolidation.

References: [EEx](https://hexdocs.pm/eex/EEx.html),
[HEEx components and keyed comprehensions](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html),
[LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html), and
[Phoenix's rendering engine](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Engine.html).
See [the ESW live guide](Documentation/LiveView.md) for lifecycle and runtime limits.

## Quick Start

### Installation

Add ESW to your application's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/roost-framework/ESW.git", from: "1.7.0"),
]
```

### Choose Your Integration

### Option A: Build Plugin (Recommended for File Templates)

The plugin compiles `.esw` and `.hesw` files into `String`-returning functions. Opt-in `.live.hesw` files return `ESWLiveRender` snapshots. Template files are explicit build inputs, so editing a template rebuilds its renderer.

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

Add the `ESW` product to your target for inline `#esw` and `#hesw` templates. They capture Swift values from the surrounding scope and need no build plugin. The `#render` file macro is deprecated: use Option A's generated renderers or a [typed view](#typed-views-no-template-header) for file templates.

### Your First Template

Create `Views/greeting.esw`:

```html
<%!
var name: String
%>
<h1>Hello, <%= name %>!</h1>
```

The build plugin generates `renderGreeting(name:)`, which returns `String`. Wrap the result with whatever your framework provides:

```swift
// Nexus
conn.html(renderGreeting(name: "World"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: renderGreeting(name: "World"))))

// Vapor
Response(body: .init(string: renderGreeting(name: "World")))
```

**Or as a typed view:** remove the `<%! ... %>` header from `greeting.esw` and declare the input on a Swift struct next to it. See [Typed Views](#typed-views-no-template-header).

```swift
@ESWTemplate("greeting.esw")
struct Greeting {
    let name: String
}

let html = Greeting(name: "World").render()
```

---

## Editor Support

The [Neovim plugin](editors/nvim) highlights HTML and embedded Swift in `.esw`
and `.hesw` templates. It reuses Neovim's built-in syntax files. Its README also
shows how to enable Tailwind CSS class completion in templates.

Tailwind CSS v4 finds class names in `.esw` and `.hesw` files without
configuration, including string literals inside expressions such as
`class={["button", active ? "active" : nil]}`. Write each class name in full:
Tailwind cannot see a name assembled at runtime, such as `"text-\(color)-500"`.

In VS Code, treat templates as HTML so the Tailwind CSS IntelliSense extension
completes classes in them:

```json
{
  "files.associations": { "*.esw": "html", "*.hesw": "html" }
}
```

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

### HTML-Aware Templates (`.hesw`)

Use `.hesw` files or the `#hesw` macro for balanced HTML tags, brace interpolation, dynamic attributes, and directives. Expressions are Swift:

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
| `:key={item.id}` with `:for` | Gives each repeated element/component a stable live-render identity |

When both directives appear, `:for` creates the scope for `:if`, regardless of their attribute order:

```html
<li :if={item.count > 0} :for={item in items}>{item.name}</li>
```

Use `:key` to keep list updates small in `#live` and `.live.hesw` templates:

```html
<ul>
  <li :for={item in items} :key={item.id} id={"item-\(item.id)"}>
    {item.name}
  </li>
</ul>
```

Prepending sends the new row, reordering sends the new key order, and editing a
row sends its changed dynamic values. Nested keyed lists retain their own scopes.
Keys must be stable and have unique JSON encodings within their list; Swift
`Encodable` values such as strings, integers and UUIDs work. Duplicate or
unencodable keys fall back to a complete HTML fragment without dropping rows.
`:key` requires `:for` on the same element or component and is not supported on
slots. It does not emit an HTML attribute: use explicit stable `id` attributes
for DOM identity and focus preservation. Ordinary `#hesw` / `.hesw` renderers
produce the same HTML with or without `:key`.

The existing `<% ... %>` tags, components, and string slots also work in HESW. Use `title={expression}` for dynamic HTML attributes; embedded `<%= ... %>` inside a quoted attribute is rejected. Attribute values are always escaped, including values marked with `render(...)`.

HTML mode reports unclosed or mismatched tags, duplicate attributes, and malformed directives with source locations. Non-void elements need closing tags or `/>`. HTML comments and the bodies of `<script>` and `<style>` keep braces literal while still evaluating `<% ... %>` tags and processing escaped EEx delimiters. A bare `phx-no-curly-interpolation` attribute applies that brace rule to an HTML element, component, or slot body and its descendants; dynamic attributes and EEx tags still work, and the control attribute is removed from the output. Use `\{` and `\}` for literal braces in body text (in a Swift literal, use a raw string or escape the backslash).

`.esw` files retain their text-template behavior: literal braces and HTML fragments are allowed. HESW is a Swift template syntax inspired by Phoenix HEEx; it does not include live state, diffing, or events.

**Note:** `.heex` files, `#heex`, `--heex`, `TemplateSyntax.heex`, and `LiveView` still work as deprecated aliases and will be removed in ESW 2.0. The `#render` file macro is also deprecated and will be removed in 2.0; see [Macros](#macros).

### Scoped Styles

A `<style :scoped>` block keeps a template's CSS beside its markup and applies it only to that template. In `.hesw` file templates, ESWBuildPlugin marks the top-level elements with a `data-esw` attribute and collects the CSS, wrapped in CSS `@scope`, into the generated `ESWStyles.css` constant for the target:

```html
<style :scoped>
  :scope { padding: 1rem; }
  .title { font-weight: 600; }
</style>
<article><h2 class="title">{title}</h2></article>
```

Selectors match elements inside the template's top-level elements, including markup passed into component slots, and stop at nested templates that have their own scoped styles. Use `:scope` for the top-level elements themselves, as in `:scope.title` or `h2:scope`; a plain `.title` does not match a top-level element.

Include the stylesheet once, for example in the layout:

```html
<style><%== ESWStyles.css %></style>
```

The block must be static CSS at the top of a file template. `#hesw` and single-file compilation reject it because they have no target stylesheet. `@scope` needs a current browser: Chrome or Edge 118, Safari 17.4, or Firefox with `@scope` support.

### Typed Views (No Template Header)

Associate an ordinary Swift file with a template using `@ESWTemplate`:

```swift
// Views/auth/RegisterView.swift
import ESW

@ESWTemplate("register.esw")
struct RegisterView {
    var email: String = ""
    var error: String? = nil

    var heading: String { "Create your account" }
}
```

`register.esw` starts directly with HTML and uses the view's members:

```html
<h1><%= heading %></h1>
<% if let error { %>
  <p role="alert"><%= error %></p>
<% } %>
<p>Email: <%= email %></p>
```

The annotation adds `ESWView` conformance. **ESWBuildPlugin must be enabled on the
same target**: it generates `RegisterView.render()` in an extension. The macro
never reads template files, so edits to a template reliably trigger recompilation.

```swift
let html = RegisterView(email: "reader@example.test").render()
```

Template paths are relative to the declaring Swift file and must identify a template
in the same target. A file may contain several annotated, unconditional top-level
structs and ordinary helper declarations. Each template belongs to one view.
Swift owns initializers, types, defaults, generics, computed properties and helpers.
Imports, including conditional imports, are copied into the generated file.
Members referenced by the template must be internal, package or public; separate
extensions cannot access `private` or `fileprivate` members. A public or package
view gets the same `render()` access level.

`.esw` and `.hesw` views return `String`; `.live.hesw` views return `ESWLiveRender`.
The build plugin tracks all target Swift sources and template files, including
when annotations are added, removed or changed. Standalone CLI use is explicit:

```sh
ESWCompilerCLI Views/auth/register.esw --view-source Views/auth/RegisterView.swift
```

Remove parameter blocks from associated templates. Typed templates generate methods
instead of legacy free functions or partial aliases. Existing header-based templates
and inline macros remain supported. The earlier experimental `.esw.swift` filename
pairing is replaced by this annotation.

HTTP request data belongs to the web framework. Roost's `try conn.render(view)`
supplies form context and the configured layout; its `<.form>` component handles
CSRF and method overrides without adding `csrfToken` or `conn` to page views.

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

ESW provides expression macros for string and live rendering, plus an attached
`@ESWTemplate` macro for typed file views. The examples below cover string macros;
see the library guides for the complete reference.

### `#render` — File Templates (Deprecated)

Deprecated in ESW 1.7 and removed in 2.0. `#render` reads a `.esw` or `.hesw` file at compile time and captures template variables from the surrounding scope. It needs `swift build --disable-sandbox`, and its file read is not a SwiftPM build input, so editing the template does not rebuild the caller. Use the build plugin's generated renderer or a [typed view](#typed-views-no-template-header) instead:

```swift
let users = try await db.query(User.self).all()

// Before
let html = #render("users.esw")

// After: users.esw declares <%! var users: [User] %>
let html = renderUsers(users: users)
```

**File resolution:** Searches `Views/<name>` and `<name>` up to 6 directory levels up.

### `#esw` — Inline Templates

For small templates:

```swift
let badge = #esw("""
    <span class="badge"><%= count %></span>
    """)
```

### `#hesw` — Inline HTML-Aware Templates

```swift
let items = ["Swift", "HTML"]
let html = #hesw("""
    <ul><li :for={item in items}>{item}</li></ul>
    """)
```

Inline macros decode normal and raw Swift string literals. Use template expressions for dynamic content; Swift string interpolation inside the template literal is rejected.

### Framework Integration

Inline macros return `String` — wrap the result with whatever your framework provides:

```swift
// Nexus
conn.html(html)

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: html)))

// Vapor
Response(body: .init(string: html))
```

**Note:** `#esw` and `#hesw` do not read template files and need no extra build flags. Only the deprecated `#render` requires `--disable-sandbox`.

---

## Build Plugin

Auto-generates Swift functions returning `String` from `.esw` and `.hesw` files.

### Generated Functions

| Filename | Generated Function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(...)` |
| `layout.esw` | `renderLayout(...)` |
| `tasks.hesw` | `renderTasks(...)` |
| `users/index.hesw` | `renderUsersIndex(...)` |
| `posts/index.esw` | `renderPostsIndex(...)` |
| `users/_card.hesw` | `renderUsersCard(...)` + `_renderUsersCardBuffer(...)` |
| `_user_card.esw` | `renderUserCard(...)` + `_renderUserCardBuffer(...)` |

### Usage

```swift
return conn.html(renderUserProfile(user: user, posts: posts))
```

**Partials** (files starting with `_`) also get a `_render…Buffer(...)` alias returning the same `String`. Both variants retain parameter defaults.

Names are relative to `Views/` (or the target directory for templates outside it). Directory names are part of the function name, so separate resources can each have `index.hesw`. Underscores and hyphens separate words in generated names. The plugin rejects filename collisions such as `user_card.esw` and `user-card.hesw`, which both generate `renderUserCard`.

### Compiler CLI

```bash
swift run ESWCompilerCLI Views/tasks.hesw --output /tmp/renderTasks.swift --source-location
```

Use `--hesw` to opt into HTML mode for a file with a different extension. A batch uses the same naming and collision checks as the plugin:

```bash
swift run ESWCompilerCLI --batch --root Sources/App --output /tmp/ESWTemplates.swift Sources/App/Views/users/index.hesw Sources/App/Views/posts/index.esw
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
let content = renderUserProfile(user: user, posts: posts)
let page = renderLayout(title: "User profile", content: content)

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

Auto-recompile `.esw` and `.hesw` files during development.

### Setup

Install fswatch 1.22 or newer:

```bash
brew install fswatch
```

### Run the Watch Script

```bash
./scripts/dev_watch.sh
```

Watches `.esw` and `.hesw` files outside `.build` and `.git`, and runs `swift build` on changes.

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

## Live Rendering and Events

`#live` uses the same HTML validation, Swift expressions, components, and escaping as `#hesw`, while keeping static HTML separate from dynamic values:

```swift
import ESWLive

struct Counter: Interactive {
    func mount(_ context: LiveContext) async throws -> Int { 0 }

    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }

    func render(_ count: Int) -> ESWLiveRender {
        #live("<button esw-click=\"increment\">Count: {count}</button>")
    }
}
```

The separate `ESWLivePeregrine` development adapter demonstrates initial pages, SSE render updates, and CSRF-protected POST events. It includes local browser assets, form bindings, DOM reconciliation, reconnect snapshots, and retained event IDs for retries. It still targets the pre-rename Peregrine API; current Roost checkouts need the adapter in Roost Playground or a corresponding migration.

With this repository and compatible Peregrine/Nexus checkouts as siblings:

```bash
./scripts/live_demo.sh
# Open http://localhost:8097
```

The launcher builds in the local cache outside the checkout, avoiding Finder metadata signing failures when the sources are in a synced `Documents` folder. See [the live rendering guide](Documentation/LiveView.md) for integration, lifecycle, bindings, tests, and limitations. This is an initial implementation with process-local state and its own protocol.

## Development

### Run Tests

```bash
swift test
```

The keyed-render check compiles real file templates, checks Swift/JavaScript wire
agreement and runs the browser client against a local fixture server. It does not
require the legacy framework adapter:

```bash
npm ci --prefix BrowserTests
npm run test:keyed --prefix BrowserTests
```

### Test Build Plugin Fixture

```bash
cd Fixtures/PluginConsumer
swift run --disable-sandbox App
```

### Integration Checks

```bash
python3 scripts/check_integration.py
```

This verifies consumer rendering, a template-only incremental rebuild, failed-batch output preservation, and negative Swift type checks for slots. Roost's generator output is checked against published ESW releases by [roost-cli](https://github.com/roost-framework/roost-cli)'s own CI.

### Hot Reload Development

```bash
# Terminal 1: Watch ESW and HESW files
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
│   ├── ESWLive/              # Live sessions, events, and browser assets
│   └── ESWCompilerCLI/       # Standalone CLI
├── Plugins/ESWBuildPlugin/   # SPM plugin
├── Tests/                    # Compiler and runtime tests
└── Fixtures/                  # Integration test app
```

### Compiler Pipeline

```
.esw / .hesw source
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

See [the engine design](Documentation/TemplateEngine.md), [the EEx/HEEx comparison](Documentation/HEExParity.md), and [the live rendering guide](Documentation/LiveView.md). String rendering and structured live snapshots share the compiler. Live state and HTTP transport live in separate layers. Async template expressions, editor formatting, Phoenix protocol compatibility, and comparative performance claims remain outside this implementation.
