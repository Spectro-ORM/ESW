# Compiling templates from a tool

Generate declarations, macro expressions, or an entire target's renderers.

## Overview

### Compile a declaration

```swift
import ESWCompilerLib

let source = """
<%!
var name: String
%>
<h1>Hello, {name}!</h1>
"""
let generated = try compile(
    source: source,
    filename: "greeting.heex",
    sourceFile: "/project/Sources/App/Views/greeting.heex"
)
```

The result declares `renderGreeting(name: String) -> String`. `filename` is the
logical name used for naming and syntax selection; `sourceFile` preserves the
original path in diagnostics and `#sourceLocation` directives. The compiler does
not read either path. You provide the loaded template contents.

Syntax defaults to `.heex` for filenames ending in `.heex`, otherwise `.esw`.
A `.live.heex` filename also selects structured live output. Override the parser
with `syntax:` when necessary, while retaining deliberate logical naming.

### Compile a batch

```swift
let templates = [
    TemplateSource(
        name: "users/index.heex",
        source: "<h1>Users</h1>",
        sourceFile: "/project/Views/users/index.heex"
    ),
    TemplateSource(
        name: "posts/index.esw",
        source: "<h1>Posts</h1>",
        sourceFile: "/project/Views/posts/index.esw"
    ),
]
let generated = try compileTemplates(templates)
```

Batches sort templates by logical name and reject generated-name collisions before
returning output. Paths may not contain `.` or `..` components. Use names relative
to a chosen template root, preserving subdirectories to avoid flat-name collisions.

The function returns a string and performs no I/O. Write the result atomically
after success if a failed build must retain its previous output. This is how the
CLI and build plugin use the compiler.

### Supply a typed view

```swift
let view = try TemplateView(
    source: "struct GreetingView { let name: String }",
    sourceFile: "/project/Views/GreetingView.swift"
)
let generated = try compile(
    source: "<h1>Hello, {name}!</h1>",
    filename: "greeting.heex",
    sourceFile: "/project/Views/greeting.heex",
    view: view
)
```

This emits a `GreetingView.render()` extension. Include both the view source and
generated source in the consumer's Swift target. A ``TemplateSource`` can carry
the same metadata for batch compilation. Direct library calls do not discover
files or read their contents.

The metadata initializer extracts a struct name, imports, and access level. Swift
still owns property resolution, initialization, generic constraints, and helper
methods. Template parameter declarations are rejected when a view is supplied.

The CLI and build plugin associate views through `@ESWTemplate`. Tools can use
``TemplateView/discover(source:sourceFile:)`` to inspect the same annotations.
Each returned `templatePath` is relative to the declaring Swift file; the caller
resolves that path, loads the template, and passes its metadata to compilation.
The direct initializer above is for tools that already know the association.

### Generate a macro expression

```swift
let expression = try compileExpression(
    source: "<p>{name}</p>",
    syntax: .heex
)
```

The result is an immediately invoked closure expression that captures names from
its surrounding scope. It has no import declarations or standalone function
wrapper. `live: true` chooses live render output; `syntax:` selects the parser
explicitly and does not derive it from `sourceFile`.

### Diagnostics and lower-level stages

The high-level pipeline tokenizes text or HTML, coalesces adjacent literal spans,
trims control-only whitespace, parses declarations, resolves component/slot trees,
validates template usage, and generates code. The public intermediate types are
available for tools that need inspection; the high-level entry points preserve
the complete behavior.

Template diagnostics include original file/line/column information when available.
Catch and print errors with `String(describing: error)` to retain those locations.
Unknown Swift names and type mismatches emerge later when generated source is
compiled. Keep `emitSourceLocations` enabled for file-based tools; expression
generation omits those directives for macro expansion.

Templates contain executable Swift. Compile only templates trusted as application
source, not arbitrary text submitted by users.
