# ESW for Peregrine

ESW compiles editable HTML templates and Swift expressions into ordinary Swift functions. The build plugin is the primary integration for Peregrine: template files are declared build inputs, parameters are checked by Swift, and rendered strings go through `conn.html(...)`.

## Design

- Template names are paths relative to `Views`: `users/index.heex` becomes `renderUsersIndex`. A batch compiler owns naming, collision diagnostics, and atomic generation; the plugin only declares inputs and one output.
- Front matter uses Swift's parser for typed parameters, multiline defaults, and explicit imports. Inline macros use imports from their enclosing Swift file. Legacy bare keyword parameter names remain accepted. Existing Peregrine templates declaring exactly `Connection` without imports retain their Nexus import; explicit imports override that compatibility path, and unrelated type names never select a framework.
- Existing `<.card>` calls `Card.render`, and existing simple string slots remain valid. Qualified function components use `<UI.card>`. Swift checks component signatures.
- `:let` on a component makes its default content a deferred Swift closure. Named slot entries with attributes, directives, bindings, or repeated names become arrays of `ESWSlot<Attributes, Input>`. Attributes have concrete Swift types; slot contents are evaluated only when the component renders them. `ESW.slots` handles conditional and repeated entries, and `renderSlot` marks their rendered HTML as trusted body content.
- Bindings belong to their slot. Default content bindings must not leak into named slots. Compiler locals avoid names used anywhere in the template, including slot bindings. Named slot entries must be direct component children in HTML mode. Conflicting attribute/slot arguments and bindings without content receive template diagnostics.
- Script/style bodies and HTML comments disable brace interpolation but still process EEx tags and escaped EEx delimiters. `phx-no-curly-interpolation` disables body braces on an HTML element, component, or slot subtree, is removed from output, and preserves dynamic attributes and EEx tags.
- All public compiler errors print file/line/column where available. Literal HTML is coalesced before emission so HTML tokenization does not create one buffer operation for every piece of an opening tag.

## Boundaries

Swift 6.3+, macOS 14+, SwiftSyntax 600 remain the package requirements. Server-side rendering remains synchronous and returns String. Live state, DOM patching, event transport, and benchmarks against competing engines require separate implementations and evidence. These features are not implied by HEEx-like syntax.

The adjacent Peregrine CLI now emits explicit compiled calls such as `conn.html(renderUsersIndex(users: users))`, supplies CSRF parameters, and uses the same resource directories for HTML routes and views. Generated front matter imports Peregrine explicitly; project manifests declare the ESW product/plugin, and development/CSS watchers include HEEx. The legacy Nexus layout convenience signature is not changed: compose String renderers and pass the result to `conn.html(...)`.

## Acceptance

Compiled runtime tests must exercise a table with typed column attributes, repeated/conditional columns, per-row `:let`, nested components, HTML escaping, optional slots, and named/default binding isolation. The plugin consumer must compile distinct `users/index` and `posts/index` templates, explicit imported types, and a multiline default. Negative tests must demonstrate source diagnostics, type mismatches, malformed slot usage, and normalized-name collisions. Incremental fixture builds must observe template-only edits.
