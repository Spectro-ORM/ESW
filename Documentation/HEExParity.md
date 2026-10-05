# HEEx-inspired templates for Peregrine

Research checked on 2026-10-04 against official documentation and source. The ESW starting state below is the working tree inspected during this task, based on `529bc12` with existing uncommitted changes. Recommendations describe intended work, not completed features or benchmark results.

Implementation follow-up: the working tree now implements the deferred/repeated typed slots, qualified function calls, interpolation boundaries, and incremental build checks recommended below. It also adds resource-path names, Swift-parsed front matter, explicit imports, and scalar-based escaping. See [the implementation contract](TemplateEngine.md), [runtime examples](../Tests/ESWTests/SlotRenderingTests.swift), and [integration checks](../scripts/check_integration.py). A subsequent [live rendering layer](LiveView.md) adds output diffs, process-local state, SSE/POST events, and browser DOM reconciliation. The research sections retain their starting-state context; async template evaluation, editor support, and comparative benchmarks remain separate work.

The strongest direction is HTML source with compiled Swift expressions, reusable typed components, and useful template diagnostics. Preserve the distinction between that rendering contract and a future Peregrine live-update system.

## What “close to EEx / LEEx / HEEx” means

Current coverage is summarized in the [README feature table](../README.md#feature-coverage-eex-heex-and-liveview).
The implementation now also supports `:key` on `:for` elements/components, including
nested keyed wire diffs in live templates. Every expression still evaluates on
render; assign dependency tracking and general component render trees remain absent.
The research and starting-state comparisons below describe the earlier baseline.

| Reference | Relevant contract |
| --- | --- |
| EEx | Embeds host-language expressions in text and can compile templates into functions. Its engine is configurable; HTML escaping is not a universal property of EEx. [EEx documentation](https://hexdocs.pm/eex/EEx.html), [Phoenix format engines](https://hexdocs.pm/phoenix_template/Phoenix.Template.html#module-html-formats). |
| LEEx | The historical LiveView EEx engine tracks dynamic content separately from static content. This is a rendering representation, not simply another interpolation delimiter. [LiveView 0.16.4 engine source](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v0.16.4/lib/phoenix_live_view/engine.ex). |
| HEEx | Adds HTML-aware parsing and component syntax. LiveView's engine returns static parts, dynamic parts, and a fingerprint; change tracking belongs to that representation. [Current engine documentation](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Engine.html), [HTML engine source](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/html_engine.ex). |

ESW can reproduce useful HEEx authoring semantics while returning complete HTML strings. WebSocket events, DOM patching, state ownership, keyed diffs, and LiveView lifecycle compatibility would be separate framework work. Do not advertise a `.heex` extension as Elixir source compatibility or LiveView protocol support.

## Starting state in ESW

- `.esw` text mode and `.heex` HTML mode already share Swift expressions, components, and generated Swift functions. HTML mode adds balanced tags, body interpolation, dynamic attributes, `:if`, and `:for`. [Tokenizer](../Sources/ESWCompilerLib/Tokenizer.swift), [HTML tokenizer](../Sources/ESWCompilerLib/HTMLTokenizer.swift).
- `<.button>` currently means `Button.render(...)`. Slots become immediately evaluated `String` arguments; repeated named slots are rejected. [Code generator](../Sources/ESWCompilerLib/CodeGenerator.swift), [resolver](../Sources/ESWCompilerLib/ComponentResolver.swift).
- Body output is escaped unless explicitly trusted; dynamic attribute values are escaped even when wrapped as trusted HTML. [Escaping](../Sources/ESW/Escape.swift), [attributes](../Sources/ESW/Attributes.swift).
- The build plugin declares each template as an input and generated Swift as an output. File macros read templates during expansion. [Build plugin](../Plugins/ESWBuildPlugin/ESWBuildPlugin.swift), [file macro](../Sources/ESWMacros/RenderMacro.swift).

## Priorities

### 1. Deferred, repeated slots with typed inputs

This enables the largest missing composition pattern: a table owns its rows and markup while its caller supplies column renderers; a form supplies a typed context to its contents.

In Phoenix, a named slot can have multiple entries, each with attributes and its own content. `render_slot(entry, value)` supplies the value bound by `:let`. The default slot's binding is not visible in named slots. Slot declarations validate required/unknown slots and attributes; Phoenix attribute declarations mainly provide compile-time warnings, not full static checking of dynamic expressions. [Component and slot documentation](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#module-slots).

For Swift, use closures with a generic input type and ordered collections of slot entries. Keep entry attributes separate from the value yielded to its body. An API such as `Slot<Input, Attributes>` is one possible design; the names are illustrative. Using `[String: Any]` for metadata would not make those metadata fields statically typed. Preserve existing string slots through an explicit compatibility path.

Illustrative target syntax, not an existing API:

```html
<UI.table rows={users}>
  <:column label="Name" :let={user}>{user.name}</:column>
  <:column label="Email" :let={user}>{user.email}</:column>
</UI.table>
```

Keep repeated entries distinct and in source order. Let the component decide whether and how often to render their bodies. Support `:if` and `:for` on entries, with loop bindings available to the condition and slot contents. The `:let` binding belongs only to the deferred body, not the entry's attributes or condition. Reject `:let` without inner content. Phoenix supports pattern bindings; a first Swift version can explicitly support only a Swift closure parameter instead of pretending to implement Elixir patterns. [Slot compilation and directive handling](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/tag_engine/compiler.ex).

### 2. Qualified component calls without breaking current components

Phoenix's `<.button>` calls a local or imported function; `<UI.button>` calls a function in another module. ESW's existing `<.button>` to `Button.render` mapping is a different convention. Add explicit qualified Swift calls while retaining that mapping. [Component classification](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/html_engine.ex), [component invocation](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/tag_engine.ex).

Keep ordinary Swift checking for parameter labels, required values, generic types, and defaults. Document argument ordering: current ESW emits attributes in source order and named slots alphabetically, while Swift function calls must match declaration order. Do not imply unordered HTML attributes work with arbitrary Swift signatures without adding an explicit argument model.

### 3. Match interpolation boundaries deliberately

Phoenix disables body `{...}` interpolation within `script` and `style`; EEx tags remain active. Its parser processes EEx before HTML tokenization, so EEx expressions also remain active inside HTML comments. ESW's inspected implementation instead consumes these regions as literal text. [Phoenix parsing pipeline](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/tag_engine/parser.ex).

Support `phx-no-curly-interpolation` as an authoring directive: body braces remain literal for the element and descendants, then interpolation resumes for siblings. Dynamic attributes remain active. The directive is removed from output. Keep HTML validation and EEx processing active. [Brace scope in the tokenizer](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/tag_engine/tokenizer.ex), [directive removal](https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/v1.2.12/lib/phoenix_live_view/tag_engine/compiler.ex).

Treat `textarea` and `title` separately: HTML classifies them as escapable raw text, distinct from `script`/`style`. That browser rule does not imply disabling template interpolation. [HTML element categories](https://html.spec.whatwg.org/multipage/syntax.html#elements-2). Test literal braces, escaped EEx delimiters, nested elements, void elements, and restoration after the closing tag.

### 4. Preserve escaping and declare intentional differences

Keep escaped body output as the default, an explicit trusted-HTML escape hatch, and attribute escaping independent of body trust. Phoenix similarly distinguishes HTML escaping from explicit `raw` content and provides separate JavaScript escaping. HTML escaping alone is not a JavaScript, CSS, or URL policy; avoid a blanket “XSS-safe” guarantee. [Phoenix.HTML](https://hexdocs.pm/phoenix_html/Phoenix.HTML.html).

Record intentional attribute differences. For example, Phoenix renders dynamic `class`/`style` with `false` or `nil` as empty strings, whereas the inspected ESW omits them; ESW gives `aria-*`/`data-*` booleans string values. These need documented contracts and examples, not accidental compatibility claims. [HEEx attribute semantics](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#sigil_H/2), [ESW attribute implementation](../Sources/ESW/Attributes.swift).

### 5. Make file-based builds and diagnostics dependable

Use the build plugin as the primary integration for Peregrine file templates and inline macros for local fragments. Verify that editing only a template regenerates its Swift and changes the rendered result; do not assume a macro's file read establishes a build dependency. SwiftPM build commands model explicit inputs/outputs. Phoenix embeds template files as functions and tracks template paths for recompilation. [SwiftPM build tools design](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md), [Phoenix.Template](https://hexdocs.pm/phoenix_template/Phoenix.Template.html).

Retain template locations through nested slots, directives, and generated closures. After syntax settles, add formatting/editor support: HEEx already has a dedicated formatter for files and inline sigils. [HTMLFormatter](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.HTMLFormatter.html).

## Relevant Swift alternatives

| Alternative | Verified strength | Useful ESW distinction or remaining work |
| --- | --- | --- |
| Leaf | External templates, `Encodable` context, conditions/loops, layout extension/import/export, and explicit unsafe HTML. [Official Vapor documentation](https://docs.vapor.codes/leaf/overview/). | Preserve familiar HTML files while compiling template expressions as Swift. Compare developer diagnostics and composition, not unsupported speed claims. |
| Stencil | General text templates, filters/tags, and contextual variable lookup including dictionaries, dynamic members, and reflection. [Language documentation](https://stencil.fuller.li/en/latest/templates.html), [template API](https://stencil.fuller.li/en/latest/api.html). | Keep `.esw` useful for text while making `.heex` an explicit HTML contract. |
| Elementary | Swift-native HTML composition, typed attributes, and documented async/streaming support. [Official repository](https://github.com/elementary-swift/elementary). | Type safety alone is not a unique advantage. ESW's opportunity is HTML authoring plus Swift checking; async/streaming remains separate work to assess against actual Peregrine needs. |

## Acceptance slice

Complete a reusable table with repeated typed column slots and a form with a typed default slot. Compile and render them through both inline macros and the build-plugin fixture. Verify:

- wrong yielded types and unknown members fail compilation at a useful template location;
- ignored slot bodies are not evaluated, repeated entries preserve order, and bindings stay in their own slot;
- slot directives filter/create entries correctly and missing required content has a clear failure;
- untrusted content escapes once, nested rendered HTML avoids double escaping, and attribute quotes remain protected;
- raw-text/EEx behavior and no-curly scope match the documented contract;
- a template-only edit changes the next build's output.

Measure build time, render time, allocations, and output equivalence on representative Peregrine pages before making performance or superiority claims. No comparative benchmark was run for this research.
