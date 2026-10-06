# ESW library documentation

The public libraries have DocC catalogs with conceptual guides and API reference
pages generated from their Swift declarations and documentation comments. They
document this development checkout; not every API is in a published ESW release.

| Library | Start here | Responsibility |
| --- | --- | --- |
| `ESW` | [Overview](../Sources/ESW/ESW.docc/ESW.md) · [Getting started](../Sources/ESW/ESW.docc/GettingStarted.md) | Templates, escaping, components, slots, assets, and structured render output. |
| `ESWLive` | [Overview](../Sources/ESWLive/ESWLive.docc/ESWLive.md) · [Writing a live view](../Sources/ESWLive/ESWLive.docc/WritingALiveView.md) | State, serialized events, retries, ownership, and browser integration. |
| `ESWCompilerLib` | [Overview](../Sources/ESWCompilerLib/ESWCompilerLib.docc/ESWCompilerLib.md) · [Compiling templates](../Sources/ESWCompilerLib/ESWCompilerLib.docc/CompilingTemplates.md) | Source generation for macros and build tools. |

## Build and browse

Use an Xcode/Swift toolchain containing `docc` with `convert` and `merge` commands,
plus Python 3:

```sh
python3 scripts/build_docs.py
```

The script builds public symbol graphs, checks all three catalogs with warnings
treated as errors, and merges them into one `.doccarchive` containing a static
website. It prints the output directory and a local HTTP-server command. Build
products default to a checkout-specific directory under `~/Library/Caches/` on
macOS, outside File Provider-managed source folders.

You can also open the resulting archive in Xcode. In an Xcode workspace containing
the package, **Product → Build Documentation** picks up the catalogs beside each
library's source files.

Choose output paths or a hosting prefix explicitly:

```sh
python3 scripts/build_docs.py \
  --output /tmp/ESW.doccarchive \
  --hosting-base-path /ESW
```

The hosting prefix must match the deployment URL. The build command creates files
locally; it does not publish a site. Run it again after changing an API comment or
guide so declarations and documentation remain in sync.

## Reading paths

- Application authors: [syntax](../Sources/ESW/ESW.docc/TemplateSyntax.md),
  [file templates and typed views](../Sources/ESW/ESW.docc/FileTemplates.md),
  [components and slots](../Sources/ESW/ESW.docc/ComponentsAndSlots.md), and
  [escaping and assets](../Sources/ESW/ESW.docc/EscapingAndAssets.md).
- Live applications: [structured rendering](../Sources/ESW/ESW.docc/LiveRendering.md),
  [lifecycle and events](../Sources/ESWLive/ESWLive.docc/LifecycleAndEvents.md), and
  [browser/HTTP integration](../Sources/ESWLive/ESWLive.docc/BrowserIntegration.md).
- Build-tool authors: [compiler APIs](../Sources/ESWCompilerLib/ESWCompilerLib.docc/CompilingTemplates.md).
- Diagnosis: [troubleshooting](../Sources/ESW/ESW.docc/Troubleshooting.md).

## Design and integration notes

[TemplateEngine.md](TemplateEngine.md) records the implementation contract.
[HEExParity.md](HEExParity.md) and [LiveViewResearch.md](LiveViewResearch.md) retain
their historical research context and distinguish implementation from proposals.
[LiveView.md](LiveView.md) describes the original Peregrine adapter and its
validation. That adapter still targets the old framework name; use a compatible
checkout, or the separate [Roost Playground](https://github.com/roost-framework/roost-playground)
integration with the renamed Roost product.
