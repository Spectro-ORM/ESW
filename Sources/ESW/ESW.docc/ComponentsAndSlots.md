# Components and slots

Compose HTML with Swift functions and pass typed, deferred content to reusable components.

## Overview

### A simple component

`<.button>` maps to `Button.render(...)`; a hyphenated `<.user-card>` maps to
`UserCard.render(...)`. The ``ESWComponent`` protocol documents this convention.
Swift checks the concrete renderer's argument labels and types.

```swift
import ESW

struct Button: ESWComponent {
    static func render(label: String, disabled: Bool = false) -> String {
        #heex("<button disabled={disabled}>{label}</button>")
    }
}

let html = #heex("<.button label=\"Save\" disabled />")
```

Quoted component attributes are Swift strings. Braced attributes are Swift
expressions, and bare attributes pass `true`. Qualified tags such as
`<UI.button label="Save" />` call `UI.button(...)` directly.

Unlike ordinary HTML attributes, component arguments follow Swift parameter
ordering: **attributes in source order, named slots alphabetically, then default
`content` last**. Give parameters defaults when callers may omit them.

### String content and named slots

Content outside a named slot becomes `content:`. A single named slot with no
attributes, directives, or binding becomes a `String` argument:

```swift
struct Card: ESWComponent {
    static func render(title: String, footer: String = "", content: String = "") -> String {
        #heex("""
        <article>
          <h2>{title}</h2>
          <div>{ESWValue.safe(content)}</div>
          <footer>{ESWValue.safe(footer)}</footer>
        </article>
        """)
    }
}

let html = #heex("""
<.card title="Profile">
  <p>Member since 2026.</p>
  <:footer>Updated today.</:footer>
</.card>
""")
```

The slot strings already contain escaped template output. `ESWValue.safe(content)`
marks that result as trusted HTML to avoid escaping its markup again. This explicit
form also avoids shadowing ESW's global `render(...)` helper inside a method named
`render`. A manually written
component is responsible for escaping any dynamic values it assembles itself.

Named slots must be direct children of the component in HTML mode. They are
arguments, not output elements; `<:footer>` itself does not appear in the HTML.

### Repeated and typed slots

Adding attributes, directives, `:let`, or repeated entries changes a named slot
into an ordered array of ``ESWSlot`` values. Each entry carries concrete attributes
and a body that the component can render with a typed input.

```swift
struct Person { let name: String }
struct ColumnAttributes { let label: String }

enum UI {
    static func table(people: [Person], column: [ESWSlot<ColumnAttributes, Person>]) -> String {
        let headings = column.map { "<th>" + ESW.escape($0.attributes.label) + "</th>" }.joined()
        let rows = people.map { person in
            "<tr>" + column.map { "<td>" + $0.render(person) + "</td>" }.joined() + "</tr>"
        }.joined()
        return "<table><thead><tr>" + headings + "</tr></thead><tbody>" + rows + "</tbody></table>"
    }
}

let people = [Person(name: "Ada")]
let showDetails = true
let html = #heex("""
<UI.table people={people}>
  <:column label="Name" :let={person}><strong>{person.name}</strong></:column>
  <:column label="Details" :if={showDetails} :let={person}>{person.name}</:column>
</UI.table>
""")
```

Attributes are evaluated at the call site. The body runs only when the component
calls `entry.render(input)`; it can render once per row or never. Use
`renderSlot(entry, input)` or `renderSlot(entries, input)` inside template expressions
to embed the resulting trusted HTML. Those helpers are for HTML-producing slot
bodies, not for bypassing escaping on arbitrary untrusted strings.

For entries without attributes, use ``ESWEmptySlotAttributes``. For entries without
input, use `Void` and the input-free `renderSlot` overloads. An optional slot array
can default to `[]` in the component signature.

### Slot scopes

- `:for` creates entries in source order; its binding is available to attributes,
  `:if`, and the body.
- `:let={person}` introduces a binding only inside the deferred body. It cannot be
  used in that entry's attributes or condition.
- Tuple bindings such as `:let={(key, value)}` are supported.
- A self-closing slot cannot bind input with `:let` because it has no body.

Wrong attribute types and unknown input members are ordinary Swift compilation
errors. Template diagnostics report malformed slot structure before Swift compilation.

### Deferred default content

Putting `:let` on a component supplies a closure as its default `content` argument:

```swift
struct FormContext { let name: String; let value: String }

struct Form: ESWComponent {
    static func render(value: String, content: (FormContext) -> String) -> String {
        "<form>" + content(FormContext(name: "name", value: value)) + "</form>"
    }
}

let name = "Ada"
let html = #heex("""
<.form value={name} :let={form}>
  <input name={form.name} value={form.value} />
</.form>
""")
```

The default content binding is not visible to named slots. Without `:let`, default
content keeps its `String` convention.
