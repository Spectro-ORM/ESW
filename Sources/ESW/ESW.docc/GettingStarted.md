# Getting started

Render a Swift value as HTML, then choose an integration for your application.

## Overview

### Add the library

For the current development APIs, put this checkout beside your application and
add it as a local Swift package dependency:

```swift
// In Package.swift:
dependencies: [
    .package(path: "../esw"),
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [.product(name: "ESW", package: "esw")]
    ),
]
```

Use the actual package identity if you give the checkout a different directory
name. Application source imports the `ESW` module.

### Render a fragment

An inline ``hesw(_:)`` template captures values from its surrounding Swift scope:

```swift
import ESW

let names = ["Ada", "Grace & Hopper"]
let html = #hesw("""
<section>
  <h1>People</h1>
  <ul><li :for={name in names}>{name}</li></ul>
</section>
""")
```

`html` is a `String`; the ampersand in the second name becomes `&amp;`.
Pass that string to your framework's HTML response method. ESW itself does not
create HTTP responses or require a particular server framework.

Dynamic expressions use Swift syntax and types. An unknown variable or missing
member becomes a Swift compiler error. The template literal must not contain
Swift string interpolation; place expressions in `{...}` or `<%= ... %>` instead.

### Choose how to author templates

| Entry point | Result | Use it for |
| --- | --- | --- |
| `#esw("...")` | `String` | Text templates and HTML fragments using EEx-style tags. |
| `#hesw("...")` | `String` | HTML-aware inline templates with brace expressions and directives. |
| `#live("...")` | `ESWLiveRender` | Structured HTML output for live updates. |
| `ESWBuildPlugin` + `.esw` / `.hesw` | Generated `String` renderer | File templates tracked as build inputs. |
| `ESWBuildPlugin` + `.live.hesw` | Generated `ESWLiveRender` renderer | Live file templates. |
| `#render("page.hesw")` | `String` | Deprecated; use `@ESWTemplate` or a generated renderer. |

Use the build plugin for file templates. The deprecated `#render` file macro does
not declare a SwiftPM dependency on its template and may require
`swift build --disable-sandbox`; it will be removed in ESW 2.0. Inline macros do
not read template files.

### Add live behavior

Add `.product(name: "ESWLive", package: "esw")` when you need the `Interactive`,
`LiveSession`, and `LiveHost` APIs. That module re-exports `ESW`. A transport adapter
is still responsible for HTTP routes, browser connections, sessions, and CSRF.

The separate [Roost Playground](https://github.com/roost-framework/roost-playground) supplies
that application setup for a one-file experiment. It also uses the current local
development dependencies. Start with <doc:LiveRendering> to understand what the
core rendering layer produces.

### Next steps

- Learn expressions, attributes, and directives in <doc:TemplateSyntax>.
- Move inputs into Swift structs with <doc:FileTemplates>.
- Compose reusable UI with <doc:ComponentsAndSlots>.
