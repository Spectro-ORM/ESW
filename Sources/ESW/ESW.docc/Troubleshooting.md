# Troubleshooting

Resolve common template, build, and editor problems.

## Overview

### A variable disappears after saving Swift

Some formatters consider a parameter unused when its only references occur inside
a template string. Guard that declaration when using SwiftFormat:

```swift
// swiftformat:disable:next unusedArguments
func render(_ count: Int) -> ESWLiveRender {
    #live("<p>{count}</p>")
}
```

For file templates, an `@ESWTemplate` view keeps its properties in ordinary Swift.

### Editing a template does not rebuild it

Use `ESWBuildPlugin` for file templates. It declares templates and Swift view files as
SwiftPM inputs. The `#render` macro reads files during expansion but does not
independently tell SwiftPM to rebuild when only that file changes. Also ensure the
target has not excluded its `Views/` directory.

### The compiler cannot see a type or property

Header-based file templates need explicit imports for external types. Typed
templates inherit imports from their associated Swift file, and their generated
extension cannot access `private` or `fileprivate` members in another file.
Inline macros use the imports and values visible at their call site. Header
defaults do not create values for a macro expansion.

### An attribute expression is rejected

In HTML mode write `value={name}`, not `value="<%= name %>"`. For a component,
argument labels and ordering must match the Swift renderer. An ordinary HTML tag
does not have component argument ordering constraints.

### `render` resolves to my view's method

Inside a method named `render`, Swift can resolve `render(content)` to that method
instead of ESW's global trusted-HTML helper. Use `ESWValue.safe(content)` for output
from a trusted renderer or slot. This is the same trust decision and still does
not sanitize arbitrary HTML.

### Two templates generate the same symbol

The plugin derives names from logical paths. `user-card.hesw` and `user_card.hesw`
both become `renderUserCard`. Rename one file. Nested names such as
`users/index.hesw` and `posts/index.hesw` remain distinct. Two templates
cannot both generate the same struct's `render()` method.

### File macros cannot read a template

Relative lookup starts at the calling Swift file, checking `Views/<path>` and
`<path>` for up to six directory levels. Absolute paths are accepted. File reads
may need `--disable-sandbox`; inline macros do not. Prefer the build plugin when
integrating an application so its filesystem inputs are explicit.

### A signed resource bundle fails in a synced folder

If macOS reports `resource fork, Finder information, or similar detritus not
allowed`, choose a SwiftPM scratch directory outside the File Provider-managed
checkout. The playground and live-demo launchers already do this. You do not need
to disable code signing or move source files merely to choose another build path.

### Live behavior differs from Phoenix

Use `esw-click`, `esw-submit`, and `esw-change` with an ESW HTTP adapter. HESW's
HEEx-inspired syntax does not imply Phoenix's transport, JavaScript client,
stateful components, or navigation APIs. Live state is process-local;
reconnecting to a retained instance differs from restarting the application.

### A template or view still uses `heex` or `LiveView`

ESW renamed the HTML-aware syntax to HESW and the live view protocol to
`Interactive`. `.heex` files, `#heex`, `--heex`, `TemplateSyntax.heex`, and
`LiveView` still work as deprecated aliases and will be removed in ESW 2.0.
Rename `.heex` and `.live.heex` files to `.hesw` and `.live.hesw`.
