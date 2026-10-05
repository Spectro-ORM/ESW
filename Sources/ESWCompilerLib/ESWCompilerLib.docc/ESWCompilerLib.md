# ``ESWCompilerLib``

Compile ESW and HEEx templates into Swift source for macros, build tools, and custom integrations.

## Overview

Most applications depend on `ESW` and its build plugin. Use this library when
building template tooling: it accepts source strings, checks template structure,
and returns Swift source. It does not execute templates or perform Swift semantic
type checking; the Swift compiler does that when it compiles the generated code.

The high-level functions share the same pipeline as ESW's macros and CLI. Prefer
them to composing compiler stages yourself so naming, declarations, validation,
and source locations remain consistent.

## Topics

### Build tools

- <doc:CompilingTemplates>
- ``compile(source:filename:sourceFile:emitSourceLocations:syntax:view:)``
- ``compileExpression(source:sourceFile:syntax:live:)``
- ``compileTemplates(_:emitSourceLocations:)``
- ``TemplateSource``
- ``TemplateView``
- ``TemplateSyntax``
- ``Naming``

### Compiler stages and intermediate data

- ``Tokenizer``
- ``Token``
- ``Metadata``
- ``WhitespaceTrimmer``
- ``AssignsParser``
- ``Parameter``
- ``TemplateDeclarations``
- ``ComponentResolver``
- ``RenderNode``
- ``ComponentNode``
- ``ComponentAttribute``
- ``ComponentAttributeValue``
- ``Slot``
- ``CodeGenerator``

### Diagnostics

- ``ESWTemplateError``
- ``ESWHTMLDiagnostic``
- ``ESWTokenizerError``
- ``ESWAssignsError``
- ``ESWComponentError``
