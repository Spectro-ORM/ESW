# File templates and typed views

Generate renderers from tracked template files, with inputs declared in Swift or in a template header.

## Overview

### Enable the build plugin

Add both the runtime product and build plugin to the target containing templates:

```swift
.executableTarget(
    name: "App",
    dependencies: [.product(name: "ESW", package: "esw")],
    plugins: [.plugin(name: "ESWBuildPlugin", package: "esw")]
)
```

Store templates under `Sources/App/Views/`. The plugin generates one Swift source
file for the target and tracks templates and Swift view sources as inputs.
Do not exclude the templates from the target or copy generated Swift into source
control; SwiftPM compiles the plugin output automatically.

### Declare inputs in a Swift view

Create `Views/GreetingView.swift` and associate it explicitly with its template:

```swift
import ESW

@ESWTemplate("greeting.hesw")
struct GreetingView {
    let name: String
    var isMember = false

    var title: String { "Hello, " + name }
}
```

And `Views/greeting.hesw`:

```html
<section>
  <h1>{title}</h1>
  <p :if={isMember}>Welcome back.</p>
</section>
```

The macro declares ``ESWView`` conformance; the build plugin generates an extension
containing `GreetingView.render() -> String` from the tracked template.
Construction, defaults, property access, and helper calls remain ordinary Swift:

```swift
let html = GreetingView(name: "Ada", isMember: true).render()
```

The path is relative to the annotated Swift file. The view filename is your choice:

| Template path | Annotation | Return type |
| --- | --- | --- |
| `greeting.esw` | `@ESWTemplate("greeting.esw")` | `String` |
| `greeting.hesw` | `@ESWTemplate("greeting.hesw")` | `String` |
| `counter.live.hesw` | `@ESWTemplate("counter.live.hesw")` | `ESWLiveRender` |

Annotate an unconditional top-level struct. Generic structs, computed properties,
defaults, and instance helpers are supported. Multiple annotated views can share a
Swift file. Imports, including conditional imports, are copied into generated code.
Public and package access are carried onto `render()`; expose an initializer
yourself if consumers in another module need to construct a public view.

The generated method lives in another file. Members it uses cannot be `private`
or `fileprivate`. An internal member is accessible within the target. Do not define
another `render()` with the same signature in the view.

Typed templates must not also declare parameters in `<%! ... %>`. They generate
an instance method, not a legacy free function or partial alias. The macro does not
read the template itself; the build plugin is required. Keep referenced templates
inside the target so SwiftPM discovers and tracks them.

### Declare inputs in a template header

For a free function, omit the annotation and put typed inputs at the beginning of
`Views/greeting.hesw`:

```html
<%!
var name: String
let isMember: Bool = false
%>
<h1>Hello, {name}!</h1>
<p :if={isMember}>Welcome back.</p>
```

Call the generated function:

```swift
let html = renderGreeting(name: "Ada", isMember: true)
```

Explicit type annotations are required. Multiline defaults and closure types are
parsed as Swift. Put imports in the header for types from another module.
For compatibility, a header declaring exactly `Connection` without explicit
imports adds `import Nexus`; new templates should specify their imports.

Expression macro expansion has a different contract: it captures variables in scope and
does not introduce header parameters or their defaults. Typed-view associations
are discovered by the build plugin and CLI, not by the deprecated `#render`.

### Generated names

| Logical path | Renderer without an associated view |
| --- | --- |
| `greeting.esw` | `renderGreeting(...)` |
| `users/index.hesw` | `renderUsersIndex(...)` |
| `posts/index.esw` | `renderPostsIndex(...)` |
| `counter.live.hesw` | `renderCounterLive(...)` |
| `users/_card.hesw` | `renderUsersCard(...)` and `_renderUsersCardBuffer(...)` |

Paths are relative to `Views/`, or the target root for templates outside it.
Hyphens and underscores separate words. A leading underscore marks a partial;
its buffer-named alias still returns `String` for ordinary templates. Defaults
are preserved on both generated functions. A batch rejects normalized collisions
such as `user-card.hesw` and `user_card.hesw`.

### Compose a layout

Render a page first, then pass the resulting HTML to another renderer:

```html
<%!
var title: String
var content: String
%>
<!doctype html>
<html lang="en">
  <head><title>{title}</title></head>
  <body>{render(content)}</body>
</html>
```

For that `layout.hesw`, call `renderLayout(title: "People", content: pageHTML)`.
Only mark trusted renderer output as HTML. User-provided text stays escaped.

### Use the compiler CLI

```sh
swift run ESWCompilerCLI Sources/App/Views/greeting.hesw \
  --view-source Sources/App/Views/GreetingView.swift \
  --output /tmp/Greeting.swift --source-location

swift run ESWCompilerCLI --batch --root Sources/App \
  --output /tmp/ESWTemplates.swift \
  Sources/App/Views/users/index.hesw Sources/App/Views/posts/index.esw
```

For annotated views, pass their Swift files with `--view-source`; the build plugin
does this for the target automatically. `--hesw` selects HTML mode
for single-file input with a different extension; batches infer syntax from each
filename. Output files are written atomically after successful generation.
