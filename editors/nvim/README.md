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
- `.hesw` and `.live.hesw` use the `hesw` filetype, which also highlights Swift
  brace expressions in HTML bodies and unquoted attributes.

Deprecated `.heex` templates keep Neovim's normal detection, including Phoenix's
`heex` filetype. Select HESW highlighting manually with `:set ft=hesw`.
Use `:set ft=esw` to select the text-oriented syntax explicitly.

Highlight groups inherit your color scheme's HTML and Swift colors. Template
delimiters and directives use `PreProc`; component names use `Type`. Comment
commands insert `<%!-- ... --%>` template comments. Changing from Phoenix HEEx to
ESW or HESW stops that buffer's old Tree-sitter highlighter.

This package provides lexical highlighting, not Swift completion, diagnostics,
formatting, or a structural Tree-sitter grammar. In particular, it does not model
the inherited `phx-no-curly-interpolation` directive: literal braces inside such
subtrees may still receive expression colors. The ESW compiler remains responsible
for validating templates.

## Tailwind CSS class completion

The Tailwind CSS language server completes and previews classes in templates. It
requires Node.js. With LazyVim's Tailwind extra
(`lazyvim.plugins.extras.lang.tailwind`), add the template filetypes to its
server options:

```lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tailwindcss = {
          filetypes_include = { "esw", "hesw" },
          settings = { tailwindCSS = { includeLanguages = { esw = "html", hesw = "html" } } },
        },
      },
    },
  },
}
```

Without LazyVim, on Neovim 0.11 or newer with nvim-lspconfig installed, extend
the server's default filetypes after plugins load:

```lua
vim.lsp.config("tailwindcss", {
  filetypes = vim.list_extend(vim.deepcopy(vim.lsp.config.tailwindcss.filetypes), { "esw", "hesw" }),
  settings = { tailwindCSS = { includeLanguages = { esw = "html", hesw = "html" } } },
})
vim.lsp.enable("tailwindcss")
```

The plugin does not configure the server itself: listing it would make LazyVim
install it for projects that do not use Tailwind.

## Verify

From the ESW repository root:

```sh
nvim --clean --headless -i NONE -l editors/nvim/tests/check.lua
```

The checks cover mixed-language boundaries, quoted HTML attributes, raw and
multiline Swift strings, string interpolation, nested comments, template escapes,
components, HESW expressions, filetype switching, and filetype detection.
