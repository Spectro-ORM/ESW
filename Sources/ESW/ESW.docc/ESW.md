# ``ESW``

Compile HTML templates and Swift expressions into typed renderers.

## Overview

ESW lets you author templates as HTML while Swift checks their expressions,
parameters, and component calls. Compilation produces ordinary Swift code;
rendering does not parse a template at runtime.

Use inline macros for small fragments, and `ESWBuildPlugin` for files that should
rebuild when you edit them. Ordinary renderers return `String`. Live renderers
return ``ESWLiveRender``, which keeps literal HTML and dynamic output separate.
The `ESWLive` library adds server-owned state and events; HTTP integration belongs
to a server adapter such as the Roost playground.

> Important: These pages describe the development checkout. Annotated typed views,
> live rendering, and other APIs shown here are not all available in published ESW
> releases. The package currently requires Swift 6.3+ and macOS 14+.

## Topics

### Learn ESW

- <doc:GettingStarted>
- <doc:TemplateSyntax>
- <doc:FileTemplates>
- <doc:ComponentsAndSlots>
- <doc:EscapingAndAssets>
- <doc:LiveRendering>
- <doc:Troubleshooting>

### Inline macros

- ``esw(_:)``
- ``hesw(_:)``
- ``live(_:)``

### Typed template views

- ``ESWTemplate(_:)``
- ``ESWView``

### HTML and reusable components

- ``ESW/ESW``
- ``ESWValue``
- ``render(_:)-func``
- ``ESWComponent``
- ``ESWSlot``
- ``ESWEmptySlotAttributes``
- ``ESWSlotBuilder``
- ``AssetManifest``

### Render output

- ``ESWBuffer``
- ``ESWLiveRender``
- ``ESWLivePatch``
- ``ESWLiveBuffer``

### Deprecated

- ``render(_:)-macro``
