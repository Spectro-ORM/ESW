# Template syntax

Choose text templates or HTML-aware templates while keeping expressions in Swift.

## Overview

### Text mode

`.esw` files and `#esw` use these tags:

| Syntax | Meaning |
| --- | --- |
| `<%= expression %>` | HTML-escaped output. |
| `<%== expression %>` | Raw HTML output. |
| `<% statements %>` | Swift code, including control flow. |
| `<%! declarations %>` | File-renderer parameters and imports, before template content. |
| `<%# comment %>` | A template comment, omitted from output. |
| `<%!-- comment --%>` | A multiline template comment. |
| `<%%` and `%%>` | Literal `<%` and `%>` delimiters. |
| `<%+ statements %>` | Code that preserves its otherwise-trimmed line. |

```swift
import ESW

let count = 2
let html = #esw("""
<% if count > 0 { %>
  <p><%= count %> items</p>
<% } else { %>
  <p>No items</p>
<% } %>
""")
```

Control-only lines are trimmed automatically. Text mode accepts literal braces
and HTML fragments without checking tag balance. `for`, `if`, and `switch` are
ordinary Swift statements. Fetch asynchronous data before rendering: template
evaluation is synchronous.

### HTML mode

HESW (HTML-aware ESW) applies to `.hesw`, `.live.hesw`, `#hesw`, and `#live`.
It validates HTML structure and supports brace expressions. EEx-style tags remain available.

```swift
import ESW

let items = ["Swift", "HTML"]
let enabled = true
let html = #hesw("""
<section class={["items", enabled ? "enabled" : nil]}>
  <p :if={items.isEmpty}>Nothing here yet.</p>
  <ul><li :for={item in items}>{item}</li></ul>
</section>
""")
```

Non-void tags require a matching closing tag or `/>`. The compiler reports
mismatched tags, duplicate attributes, and malformed directives at their template
locations. Void HTML elements such as `input` do not need an end tag.

### Dynamic attributes

Use `name={expression}` rather than interpolating inside a quoted attribute:

```html
<input name="email" value={email} disabled={isSaving} />
<button aria-expanded={expanded} class={["button", active ? "active" : nil]}>
  Toggle
</button>
<a {linkAttributes}>Details</a>
```

`linkAttributes` is a `[String: Any?]` map. It is expanded in sorted key order.
Invalid attribute names are omitted; expressions still need to choose appropriate
attribute names and URL values for the application.

| Value | Output |
| --- | --- |
| `nil` | Attribute omitted. |
| `true` / `false` | Bare boolean attribute / omitted attribute. |
| Boolean for `aria-*` or `data-*` | Quoted `"true"` / `"false"`. |
| A `class` array | Flattened names joined by spaces; nil, boolean, and empty entries ignored. |
| Other values | Quoted, HTML-escaped string representation. |

Trusted body HTML is still escaped in attributes. See <doc:EscapingAndAssets>.

### Directives and scope

`:for` introduces the Swift loop binding before evaluating `:if`, regardless of
their order in the tag:

```html
<li :if={item.isVisible} :for={item in items}>{item.name}</li>
```

Directives also work on components and typed slot entries. `:let` belongs to
component/slot content, not ordinary HTML elements; see <doc:ComponentsAndSlots>.

`:key={item.id}` alongside `:for` gives rows stable identities for live diffing.
It works on elements and function components, including nested lists, but not
slot entries. Use stable, unique `Encodable` keys. String templates render the
same HTML; the directive does not emit a DOM attribute. See <doc:LiveRendering>.

### Literal braces and raw-text regions

HTML comments, `script` bodies, and `style` bodies preserve braces literally.
EEx tags inside those regions are still evaluated; do not assume a comment hides
a template expression. `textarea` and `title` still interpolate template braces.

A bare `phx-no-curly-interpolation` attribute disables body brace interpolation
for an element, component, or slot subtree. ESW removes that control attribute
from output. Dynamic attributes and EEx tags remain active.

Use `\{` and `\}` for literal braces in interpolated body text. In a Swift literal,
use a raw string so Swift preserves those backslashes:

```swift
let html = #hesw(#"<p>Use \{name\} as a placeholder.</p>"#)
```

The syntax is inspired by EEx and HEEx, but expressions are Swift and the live
runtime has its own protocol. Elixir expressions and Phoenix client attributes
are not interchangeable with ESW expressions and `esw-*` bindings.
