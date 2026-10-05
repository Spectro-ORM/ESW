# Escaping and assets

Keep HTML text, trusted markup, attributes, and asset paths explicit.

## Overview

### Escaped body output

`<%= value %>` and `{value}` call ``ESW/escape(_:)``. The characters `&`, `<`, `>`,
`"`, and `'` become HTML entities. Nested optionals are unwrapped; a missing value
renders as an empty string. Booleans render as `true` or `false`.

```swift
import ESW

let name: String? = "<Ada & Grace>"
let html = #heex("<p>{name}</p>")
// <p>&lt;Ada &amp; Grace&gt;</p>
```

### Trusted HTML

Use the `render(...)` function to embed output from another trusted renderer:

```swift
let child = #heex("<strong>{name}</strong>")
let page = #heex("<main>{render(child)}</main>")
```

The function returns ``ESWValue/safe(_:)``. It differs from the `#render(...)` macro,
which reads a template file. `<%== html %>` is another explicit raw-output escape
hatch. Neither operation sanitizes its input.

``ESWValue/unsafe(_:)`` means the string still needs escaping. Constructing one is
not necessary for ordinary strings, which already receive default escaping.

### Attribute boundaries

``ESW/attribute(_:_:)`` escapes both safe and unsafe strings for a quoted attribute.
Trust for an HTML body never bypasses attribute escaping. Dynamic HEEx attributes
and spreads use these helpers automatically.

HTML escaping does not establish a URL scheme policy, sanitize HTML, encode
JavaScript, or encode CSS. For example, `href={url}` quotes and escapes the value
but does not reject a `javascript:` scheme. Choose allowable URL values in your
application. Serialize script data for its actual JavaScript/HTML context rather
than inserting a user string into a script body.

### Fingerprinted assets

``AssetManifest`` looks up filenames produced by your asset pipeline:

```swift
let assets = AssetManifest(entries: ["app.css": "/assets/app-a1b2.css"])
let html = #heex("<link rel=\"stylesheet\" href={assets.path(for: \"app.css\")} />")
```

A JSON file can supply the same `[String: String]` mapping:

```swift
let assets = try AssetManifest(jsonPath: "Public/manifest.json")
let path = assets.path(for: "app.css")
```

A missing key returns its original name. The manifest is immutable once loaded;
recreate it to pick up file changes. ESW does not fingerprint or serve assets, and
does not prepend a public directory or URL prefix to the mapped values.
