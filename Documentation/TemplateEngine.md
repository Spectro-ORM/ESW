# ESW for Roost

ESW compiles editable HTML templates and Swift expressions into ordinary Swift functions. The build plugin is the primary integration for Roost: template files are declared build inputs, parameters are checked by Swift, and rendered strings go through `conn.html(...)`.

## Design

- Template names are paths relative to `Views`: `users/index.hesw` becomes `renderUsersIndex`. A batch compiler owns naming, collision diagnostics, and atomic generation; the plugin only declares inputs and one output.
- `@ESWTemplate("relative/path.esw")` on an unconditional top-level struct opts into typed views. Ordinary Swift filenames and multiple views per file are supported. The macro declares `ESWView` conformance without filesystem reads; the build plugin tracks all Swift sources and templates, and the CLI resolves annotations before generating `render()` extensions. Missing/duplicate associations, private types, nested/conditional declarations and template parameter blocks are rejected. Swift supplies types, initializers, defaults, generics and helpers. Imports, conditional imports and public/package visibility are preserved.
- Front matter uses Swift's parser for typed parameters, multiline defaults, and explicit imports. Inline macros use imports from their enclosing Swift file. Legacy bare keyword parameter names remain accepted. Existing Peregrine templates declaring exactly `Connection` without imports retain their Nexus import; explicit imports override that compatibility path, and unrelated type names never select a framework.
- Existing `<.card>` calls `Card.render`, and existing simple string slots remain valid. Qualified function components use `<UI.card>`. Swift checks component signatures.
- `:let` on a component makes its default content a deferred Swift closure. Named slot entries with attributes, directives, bindings, or repeated names become arrays of `ESWSlot<Attributes, Input>`. Attributes have concrete Swift types; slot contents are evaluated only when the component renders them. `ESW.slots` handles conditional and repeated entries, and `renderSlot` marks their rendered HTML as trusted body content.
- Bindings belong to their slot. Default content bindings must not leak into named slots. Compiler locals avoid names used anywhere in the template, including slot bindings. Named slot entries must be direct component children in HTML mode. Conflicting attribute/slot arguments and bindings without content receive template diagnostics.
- Script/style bodies and HTML comments disable brace interpolation but still process EEx tags and escaped EEx delimiters. `phx-no-curly-interpolation` disables body braces on an HTML element, component, or slot subtree, is removed from output, and preserves dynamic attributes and EEx tags.
- `:key` with `:for` identifies repeated HTML elements or function components. Live templates keep each comprehension in one dynamic slot and recursively diff rows by key; plain templates produce the same HTML. Keys use stable, unique JSON encodings of Swift `Encodable` values. Duplicate or unencodable keys preserve output with a full-fragment fallback. Slots reject `:key`; DOM identity still uses explicit `id` attributes.
- All public compiler errors print file/line/column where available. Literal HTML is coalesced before emission so HTML tokenization does not create one buffer operation for every piece of an opening tag.

## Boundaries

Swift 6.3+, macOS 14+, SwiftSyntax 600 remain the package requirements. Template evaluation is synchronous. Ordinary templates return `String`; `#live` and `.live.hesw` opt into static/dynamic `ESWLiveRender` snapshots. The separate [ESWLive runtime and Peregrine adapter](LiveView.md) provide live state, DOM patching, and event transport. Async template evaluation and benchmarks against competing engines remain separate work.

The adjacent Roost CLI generates annotated Swift view structs and headerless templates.
`try conn.render(view)` supplies request context and the application's layout.
Roost owns its `<.form>` component, CSRF middleware and method overrides; ESW has
no dependency on HTTP, sessions or Roost. Page view inputs only describe application
data. Existing free renderers and `conn.html(...)` remain available.

## Acceptance

Compiled runtime tests must exercise a table with typed column attributes, repeated/conditional columns, per-row `:let`, nested components, HTML escaping, optional slots, and named/default binding isolation. The plugin consumer must compile distinct `users/index` and `posts/index` templates, explicit imported types, and a multiline default. Negative tests must demonstrate source diagnostics, type mismatches, malformed slot usage, and normalized-name collisions. Incremental fixture builds must observe template-only edits.

Typed-view fixtures also compile ordinary ESW, generic HESW (HTML-aware ESW), and structured live methods; exercise properties, helpers, optional errors, and escaped values; reject misspelled members and wrong initializer types; verify public methods from another module; and prove that edits to either the template or the annotated Swift source regenerate the renderer.

Keyed comprehension tests cover insert/reorder/update/delete, nested scopes, empty lists, row shape changes, component slots, duplicate-key recovery, and malformed snapshots. `npm run test:keyed --prefix BrowserTests` consumes real Swift-encoded patches and verifies JavaScript reconstruction plus browser focus, selection, row identity and draft preservation.
