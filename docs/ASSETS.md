# ESW Assets

This guide covers asset fingerprinting for cache-busting in production.

## Asset Manifest

ESW provides `AssetManifest` for mapping logical asset names to fingerprinted filenames.

### Creating a Manifest

Build tools like Vite, Parcel, or esbuild can generate a manifest file:

```json
{
  "app.css": "app-abc123.css",
  "app.js": "app-def456.js",
  "logo.svg": "logo-xyz789.svg"
}
```

Save this as `public/manifest.json` (or your build output directory).

### Using AssetManifest

```swift
import ESW

// Load the manifest at app startup
let manifest = try AssetManifest(jsonPath: "public/manifest.json")

// Make it available to templates (e.g., as a global function)
func assetPath(_ name: String) -> String {
    manifest.path(for: name)
}
```

### In Templates

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
<!-- Renders: <link rel="stylesheet" href="app-abc123.css"> -->

<script src="<%= assetPath("app.js") %>"></script>
<!-- Renders: <script src="app-def456.js"></script> -->
```

### Fallback Behavior

If an asset is not found in the manifest, `path(for:)` returns the original name:

```swift
manifest.path(for: "missing.css")  // Returns "missing.css"
```

This ensures templates work correctly even with incomplete manifests.

### Example Integration

```swift
// App main.swift
import ESW

let manifest = try AssetManifest(jsonPath: "public/manifest.json")

// Add to your template context
func renderPage(_ template: String, title: String) -> String {
    let html = #esw("""
        <!DOCTYPE html>
        <html>
          <head>
            <title><%= title %></title>
            <link rel="stylesheet" href="<%= assetPath("app.css") %>">
          </head>
          <body>
            <%= content %>
          </body>
        </html>
    """)

    // Interpolate the template with assetPath available
    return renderTemplate(html, ["assetPath": assetPath])
}
```

### Testing

```swift
import Testing
@testable import ESW

@Suite("AssetManifest")
struct AssetManifestTests {
    @Test func lookupExistingEntry() throws {
        let manifest = AssetManifest(entries: [
            "app.css": "app-abc123.css"
        ])
        #expect(manifest.path(for: "app.css") == "app-abc123.css")
    }

    @Test func missingEntryFallsBackToName() throws {
        let manifest = AssetManifest(entries: [:])
        #expect(manifest.path(for: "missing.js") == "missing.js")
    }
}
```
