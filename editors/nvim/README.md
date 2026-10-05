# ESW for Neovim

HTML and Swift syntax highlighting for ESW templates, using Neovim's built-in
syntax files. No Tree-sitter parser installation is required. Requires Neovim
0.10 or newer; validated with Neovim 0.12.

## Install

Add this local plugin specification to your lazy.nvim or LazyVim configuration:

```lua
return {
  {
    name = "esw.nvim",
    dir = "/path/to/esw/editors/nvim",
    lazy = false,
  },
}
```

Restart Neovim after adding the plugin. Without a plugin manager, add the runtime
directory to your `runtimepath` in `init.lua`:

```lua
vim.opt.runtimepath:prepend("/path/to/esw/editors/nvim")
```

## Filetypes

- `.esw` uses the `esw` filetype: HTML, Swift declarations and code/output tags,
  template comments, escapes, component tags, named slots, and component attributes.
- `.heex` and `.live.heex` use `eswheex` when the nearest project manifest is a
  `Package.swift` containing a quoted `ESW`, `ESWLive`, or `ESWBuildPlugin` name.
  This also highlights Swift brace expressions in HTML bodies and unquoted attributes.
- Other `.heex` files retain their existing detection, including Phoenix's `heex`
  filetype. A nearer `mix.exs` takes precedence over an enclosing Swift package.

If your project does not use a recognizable SwiftPM manifest, select the filetype
manually with `:set ft=eswheex`, or add a project-specific `vim.filetype.add` rule.
Use `:set ft=esw` to select the text-oriented syntax explicitly.

Highlight groups inherit your color scheme's HTML and Swift colors. Template
delimiters and directives use `PreProc`; component names use `Type`. Comment
commands insert `<%!-- ... --%>` template comments. Changing from Phoenix HEEx to
ESW stops that buffer's old Tree-sitter highlighter.

This package provides lexical highlighting, not Swift completion, diagnostics,
formatting, or a structural Tree-sitter grammar. In particular, it does not model
the inherited `phx-no-curly-interpolation` directive: literal braces inside such
subtrees may still receive expression colors. The ESW compiler remains responsible
for validating templates.

## Verify

From the ESW repository root:

```sh
nvim --clean --headless -i NONE -l editors/nvim/tests/check.lua
```

The checks cover mixed-language boundaries, quoted HTML attributes, raw and
multiline Swift strings, string interpolation, nested comments, template escapes,
components, HEEx expressions, filetype switching, and Phoenix detection.
