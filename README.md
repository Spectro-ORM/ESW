# ESW — Embedded Swift Web Templates

A compile-time HTML template engine for Swift. Write `.esw` files with familiar ERB/EEx-style syntax, get type-safe Swift functions with zero runtime overhead.

## Overview

ESW transforms HTML templates into Swift code at compile time. Designers work with familiar HTML syntax, while Swift developers get type safety, compile-time error checking, and zero runtime parsing overhead.

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
// Macro path — returns String, framework-agnostic
return conn.html(#render("donut_list.esw"))

// Build plugin path — generates a named function
return renderDonutList(conn: conn, donuts: donuts)
```

## Key Features

- **Just HTML.** No DSL to learn. Designers can edit `.esw` files without knowing Swift.
- **Compile-time safety.** Templates become Swift code at build time. Typos are compiler errors pointing at the `.esw` file.
- **Zero runtime overhead.** No template parsing, no file I/O per request, no template cache to manage.
- **XSS-safe by default.** `<%= %>` HTML-escapes all output. Raw output requires explicit `<%== %>`.
- **Component slots.** Build reusable UI components with named content regions using `<.card><:header>...</:header></.card>` syntax.
- **Two integration paths.** Swift macros (`#render`, `#esw`) for framework-agnostic use, or an SPM build plugin for auto-generated functions.
- **Hot reload.** Development watch script for automatic recompilation when `.esw` files change.

## Tech Stack

- **Language:** Swift 6.3+
- **Platforms:** macOS 14+
- **Dependencies:**
  - swift-syntax (for macros)
  - swift-algorithms (for component slot resolution)
- **Integration:** Swift Package Manager (macros or build plugin)
- **Testing:** Swift Testing framework

## Requirements

- Swift 6.3 or higher
- macOS 14 or higher
- For hot reload: `fswatch` (install via `brew install fswatch`)

## Installation

Add ESW to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alembic-labs/swift-esw", from: "0.1.0"),
]
```

### Macro Path (Recommended)

Framework-agnostic integration using Swift macros:

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

```bash
swift build --disable-sandbox
```

### Build Plugin Path

Auto-generates Swift functions from `.esw` files:

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

No `--disable-sandbox` needed. The build plugin auto-discovers `.esw` files and generates Swift functions during build.

## Getting Started

### 1. Create Your First Template

Create `Views/welcome.esw`:

```html
<%!
var name: String
%>
<h1>Welcome, <%= name %>!</h1>
<p>This is your first ESW template.</p>
```

### 2. Use the Template

**With macros (framework-agnostic):**

```swift
func handleRequest(conn: Connection, name: String) -> Connection {
    return conn.html(#render("welcome.esw"))
}
```

**With build plugin (auto-generated function):**

```swift
func handleRequest(conn: Connection, name: String) -> Connection {
    return renderWelcome(conn: conn, name: name)
}
```

### 3. Build and Run

```bash
swift build
swift run App
```

## Template Syntax

### Tag Reference

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
| `<.component />` | Component | Self-closing component tag |
| `<:slot>` | Slot region | Named content slot within component |

### Variables (Assigns)

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

### Control Flow

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

### Whitespace Trimming

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

## Component Tags

ESW supports a React/Vue-inspired component syntax for reusable UI elements.

### Self-Closing Components

```html
<.button label="Click me" />
<.button label="Delete" disabled />
<.user-card user={currentUser} />
```

Components map to Swift types conforming to `ESWComponent`:

```swift
struct Button: ESWComponent {
    static func render(label: String, disabled: Bool = false) -> String {
        """<button\(disabled ? " disabled" : "")>\(ESW.escape(label))</button>"""
    }
}

struct UserCard: ESWComponent {
    static func render(user: User) -> String {
        """
        <div class="card">
            <h2>\(ESW.escape(user.name))</h2>
            <p>\(ESW.escape(user.email))</p>
        </div>
        """
    }
}
```

### Component Slots

Pass rendered HTML fragments to components using named slots:

```html
<.card title="User Profile">
  <:header>
    <h1><%= user.name %></h1>
  </:header>
  <:footer>
    <small>Last updated: <%= user.updatedAt %></small>
  </:footer>
  <p>Bio: <%= user.bio %></p>
</.card>
```

Component implementation:

```swift
struct Card: ESWComponent {
    static func render(
        title: String,
        header: String = "",       // Named slot (alphabetical)
        footer: String = "",       // Named slot (alphabetical)
        content: String = ""       // Default slot (always last)
    ) -> String {
        """
        <div class="card">
            <div class="card-title">\(ESW.escape(title))</div>
            \(header)    <!-- Named header slot -->
            <div class="card-body">
                \(content)  <!-- Default content slot -->
            </div>
            \(footer)    <!-- Named footer slot -->
        </div>
        """
    }
}
```

### Slot Syntax

- `<:name>...</:name>` — Named slot region
- Bare content outside named slots → implicit `content:` slot
- Slots support full ESW syntax: `<%= %>`, `<% %>`, nested `<.components>`

**Default slot only:**

```html
<.card>
  <p>Body content here</p>
</.card>
```

**Named slots only:**

```html
<.layout>
  <:head><title>Hello</title></:head>
  <:body><p>Content</p></:body>
</.layout>
```

**Mixed named + default:**

```html
<.card title="Hello">
  <:header>Welcome</:header>
  <p>This is bare content → goes to content:</p>
</.card>
```

### Component Naming

- Kebab-case tag names map to PascalCase types: `<.user-card>` → `UserCard`
- Hyphenated attribute names map to underscores: `phx-click="..."` → `phx_click:`

## Macros

### `#render` — File-Based Templates

Reads a `.esw` file at compile time and expands to a `String`-returning closure. Template variables are captured from the surrounding scope:

```swift
let donuts = try await db.query(Donut.self).all()
return conn.html(#render("donut_list.esw"))
```

**File Resolution:** The file is resolved by walking up from the source file, checking `Views/<name>` and `<name>` directly at each level (up to 6 hops).

### `#esw` — Inline Templates

For small templates that don't need a separate file:

```swift
let badge = #esw("""
    <span class="badge"><%= count %></span>
    """)
```

**Important:** Swift interpolation (`\(...)`) is rejected in `#esw` — use `<%= %>` instead.

### Framework-Agnostic Usage

Both macros return `String`. Wrap with whatever your framework provides:

```swift
// Nexus
conn.html(#render("page.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("page.esw"))))

// Vapor
Response(body: .init(string: #render("page.esw")))
```

## Build Plugin

The build plugin generates named Swift functions from `.esw` files automatically:

| Filename | Generated function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(conn:...)` |
| `layout.esw` | `renderLayout(conn:...)` |
| `_user_card.esw` | `renderUserCard(conn:...)` + `_renderUserCardBuffer(...)` |

**Partials** (files starting with `_`) get both a `Connection`-returning function and a `String`-returning buffer variant for embedding in parent templates.

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

### Explicit Composition

```swift
// With macros
let body = #render("user_profile.esw")
let page = #render("layout.esw")  // title and content captured from scope

// With build plugin
let body = _renderUserProfileBuffer(user: user)
return renderLayout(conn: conn, title: user.name, content: body)
```

### Layout Helper (Nexus)

Nexus provides a convenience helper for layout composition:

```swift
return conn.html(title: "My Page", layout: renderLayout) {
    _renderUserProfileBuffer(user: user)
}
```

## Escaping

`<%= %>` runs all output through `ESW.escape()`, which replaces `&`, `<`, `>`, `"`, and `'` with HTML entities. Numbers and booleans pass through unescaped.

### Embedding Pre-Rendered HTML

To embed pre-rendered HTML without double-escaping, use `render()`:

```html
<%= render(_renderCardBuffer(user: user)) %>
```

Or use `<%== %>` for raw output:

```html
<%== _renderCardBuffer(user: user) %>
```

## Asset Fingerprinting

`AssetManifest` maps logical filenames to fingerprinted paths for cache-busting:

```swift
let manifest = try AssetManifest(jsonPath: "public/manifest.json")
func assetPath(_ name: String) -> String { manifest.path(for: name) }
```

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
<!-- renders: <link rel="stylesheet" href="app-abc123.css"> -->
```

**Manifest format:**

```json
{
  "app.css": "app-abc123.css",
  "app.js": "app-def456.js",
  "logo.svg": "logo-xyz789.svg"
}
```

**Fallback behavior:** If an asset is not found in the manifest, `path(for:)` returns the original name.

## Hot Reload

During development, ESW supports automatic recompilation of `.esw` files when they change.

### Using the Watch Script

```bash
./scripts/dev_watch.sh
```

This script:
- Watches all `.esw` files in your project (excluding `.build` and `.git` directories)
- Automatically runs `swift build` when changes are detected
- Shows build status (success/failure)

### Requirements

The watch script requires `fswatch`:

```bash
brew install fswatch
```

### Manual Approach

If you prefer not to use `fswatch`:

```bash
# After editing .esw files
swift build
```

### Integration with Server Restart

For full-stack hot reload:

```bash
# Terminal 1: Watch ESW files
./scripts/dev_watch.sh

# Terminal 2: Run your app with auto-restart
swift run App --watch
```

## Error Messages

Compiler errors point at the `.esw` file, not generated code:

```
Views/user_profile.esw:5:22: error: value of type 'User' has no member 'naem'
```

### Component Errors

The `ComponentResolver` provides clear diagnostics for structural errors:

```
Views/card.esw:3:1: error: unmatched component close '</.card>' without matching open tag
Views/card.esw:5:3: error: duplicate slot 'header' — slot names must be unique
Views/card.esw:10:1: error: slot '<:footer>' outside component context
```

### Macro Diagnostics

The `#render` macro gives clear diagnostics for common mistakes:

```
error: #render expects a file path (e.g. #render("template.esw")), not inline HTML.
       Use #esw("...") for inline templates.
```

## Architecture

```
swift-esw/
├── Sources/
│   ├── ESW/                  # Runtime library
│   │   ├── ESWBuffer.swift         # String buffer for template output
│   │   ├── ESWComponent.swift      # Component protocol
│   │   ├── ESWValue.swift          # Box type for Any values
│   │   ├── Escape.swift            # HTML escaping
│   │   ├── AssetManifest.swift     # Asset fingerprinting
│   │   └── Macros.swift            # Public macro declarations
│   ├── ESWCompilerLib/       # Core compiler (zero dependencies)
│   │   ├── Token.swift             # Token types
│   │   ├── Tokenizer.swift         # .esw → [Token]
│   │   ├── WhitespaceTrimmer.swift # Trim control-only lines
│   │   ├── AssignsParser.swift     # Extract <%! %> parameters
│   │   ├── ComponentResolver.swift # Build component tree with slots
│   │   ├── RenderNode.swift        # Component tree structure
│   │   ├── CodeGenerator.swift     # [RenderNode] → Swift code
│   │   ├── Compiler.swift          # Main pipeline
│   │   ├── Errors.swift            # Error types
│   │   └── Naming.swift            # Naming conventions
│   ├── ESWCompilerCLI/       # CLI wrapper for build plugin
│   │   └── main.swift
│   └── ESWMacros/             # Swift macro implementations
│       ├── Plugin.swift             # CompilerPlugin registration
│       ├── RenderMacro.swift        # #render("file.esw")
│       └── InlineESWMacro.swift     # #esw("...")
├── Plugins/
│   └── ESWBuildPlugin/       # SPM build tool plugin
├── Tests/
│   ├── ESWCompilerLibTests/  # 130+ tests across 11 suites
│   │   ├── TokenizerTests.swift
│   │   ├── ComponentResolverTests.swift
│   │   ├── ComponentTagTests.swift
│   │   ├── IntegrationTests.swift
│   │   ├── HardeningTests.swift
│   │   └── ...
│   └── ESWTests/
├── Fixtures/
│   └── PluginConsumer/       # End-to-end integration test fixture
├── scripts/
│   └── dev_watch.sh          # Hot reload watch script
└── docs/
    ├── DEVELOPMENT.md        # Development workflow
    └── ASSETS.md             # Asset fingerprinting guide
```

### Compiler Pipeline

```
.esw file
    ↓
Tokenizer → [Token]
    ↓
WhitespaceTrimmer → [Token] (trimmed)
    ↓
AssignsParser → parameters (from <%! %>)
    ↓
ComponentResolver → [RenderNode] (component tree)
    ↓
CodeGenerator → Swift code string
```

## Development Workflow

### Running Tests

```bash
swift test
```

### Testing Build Plugin End-to-End

```bash
cd Fixtures/PluginConsumer && swift run App
```

### Hot Reload Development

```bash
# Terminal 1: Watch .esw files
./scripts/dev_watch.sh

# Terminal 2: Run your app
swift run App
```

### Build Without Sandbox

For macro usage:

```bash
swift build --disable-sandbox
```

## Available Scripts

| Command | Description |
|---------|-------------|
| `swift test` | Run full test suite |
| `swift build` | Build the project |
| `swift build --disable-sandbox` | Build with macros (allows file reads) |
| `./scripts/dev_watch.sh` | Watch .esw files and rebuild on changes |
| `cd Fixtures/PluginConsumer && swift run App` | Test build plugin end-to-end |

## Security Considerations

- **XSS Prevention:** `<%= %>` always HTML-escapes output. Use `<%== %>` only for trusted content.
- **No Runtime Eval:** Templates compile to Swift code. No string interpolation or `eval()` at runtime.
- **Type Safety:** Template variables are Swift types. The compiler catches type mismatches.
- **No File I/O at Runtime:** Templates are read at compile time. No template directory traversal attacks.

## Performance Characteristics

- **Zero Runtime Parsing:** Templates are compiled to native Swift functions.
- **No Template Cache:** Since there's no runtime parsing, there's nothing to cache.
- **Minimal Allocations:** `ESWBuffer` uses a single `String` buffer for output.
- **Compile-Time Cost:** Template compilation happens during `swift build`, not at runtime.

## Platform Support

- **macOS 14+** (required for Swift 6.3+)
- **Swift 6.3+**
- **SPM-based projects** (no Xcode project support currently)

## Known Limitations

- **Sandbox Constraint:** Swift macro sandbox (macOS `sandbox-exec`) blocks file reads from the home directory. Workaround: `swift build --disable-sandbox`. Production fix would require a different file-passing mechanism.
- **No Streaming:** Templates render to a complete `String` before sending. Streaming/chunked responses are not supported.
- **No Template Inheritance:** ESW uses explicit composition (partials + layouts), not template inheritance like Django/Jinja.
- **Build Plugin Coupling:** The build plugin generates code that imports `Nexus`. Use the macro path for framework-agnostic code.

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass: `swift test`
2. New features include tests
3. Code follows Swift style conventions
4. Documentation is updated for user-facing changes

## License

MIT

---

**ESW** — Embedded Swift Web Templates. Compile-time safety, runtime performance, designer-friendly syntax.
