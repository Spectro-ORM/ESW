-- Run from the repository root:
-- nvim --clean --headless -i NONE -l editors/nvim/tests/check.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.cmd("filetype plugin on")
vim.cmd("syntax enable")
vim.cmd("runtime plugin/esw.lua")
local checks = 0

local function eq(expected, actual, label)
  assert(vim.deep_equal(expected, actual), label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
  checks = checks + 1
end

local function buffer(source, filetype)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(source, "\n", { plain = true }))
  vim.bo.filetype = filetype or "esw"
end

local function group(needle, offset)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local column = line:find(needle, 1, true)
    if column then
      local id = vim.fn.synID(row, column + (offset or 0), 1)
      return vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
    end
  end
  error("Missing sample: " .. needle)
end

local function expect(needle, expected, offset)
  eq(expected, group(needle, offset), needle)
end

buffer([[
<%!
import Roost
var error: String?
var name: String = "Ada"
%>
<section class="auth">
  <% if let error { %><p role="alert"><%= error %></p><% } %>
  <input value="before <%= name %> after" required>
  <.badge :if={true} :for={name in names} :key={name} label={name} />
  <UI.card title={name}><:header>Title</:header></UI.card>
</section>]])
expect("<%!", "PreProc")
expect("import", "PreProc")
expect("var error", "PreProc")
expect("String?", "Type")
expect('"Ada"', "String")
expect("<section", "Statement", 1)
expect('class="auth"', "Type")
expect('"auth"', "String")
expect("if let", "Statement")
expect("<%= error", "PreProc")
expect("<%= error", "Identifier", 4)
expect("<%= name", "Identifier", 4)
expect(' after"', "String", 1)
expect(":if", "PreProc")
expect(":key", "PreProc")
expect("{true}", "Constant", 1)
expect("label={name}", "Identifier", 7)
expect("title={name}", "Identifier", 7)
expect("<.badge", "Type", 1)
expect("<UI.card", "Type", 1)
expect("<:header", "Type", 1)
expect("</UI.card", "Type", 2)
eq("<%!-- %s --%>", vim.bo.commentstring, "template comment command")

for _, expression in ipairs({
  '"%>"',
  [["escaped \" %> still a string"]],
  [[#"%> "#]],
  [[##"quote " %> "# still raw"##]],
  '"""\n%> and " inside a multiline string\n"""',
  '#"""\n%> and " inside a raw multiline string\n"""#',
  [["value \(greet("%>"))"]],
  [["literal <%= String %>"]],
  "/* outer %> /* nested %> */ still a comment */ 42",
  "// ignored %>\n42",
}) do
  buffer('<%= ' .. expression .. ' %><p class="after">done</p>')
  eq("Type", group('class="after"'), "HTML after " .. expression)
  expect('"after"', "String")
end

buffer([[<%# ignored " %%> still a comment %><p class="back">yes</p>
<%!-- ignored %> and <%= name %> until --%><b>bold</b>
<%%= literal %%>
<p>{literal}</p>]])
expect("still a comment", "Comment")
expect('class="back"', "Type")
expect("and <%= name", "Comment")
expect("<%%", "Special")
eq("", group("literal %%>"), "escaped opening is plain text")
eq("", group("{literal}", 1), "ESW body braces are plain text")

buffer([[<%== rawHTML %><p>next</p>]])
expect("<%==", "PreProc", 3)
expect("rawHTML", "Identifier")
expect("<p>", "Statement", 1)

buffer([[<section :if={true} class={["one", "two"]}>
<p>{rows.map { row in row.name }.joined()}</p>
<input title={"}"} value="literal {value}">
<script>const js = { javascript: true };</script>
<style>.example { color: red; }</style>
<!-- {htmlComment} -->
<p>\{escaped}</p>
</section>]], "hesw")
expect(":if", "PreProc")
expect("{true}", "Constant", 1)
expect('"one"', "String")
expect("rows.map", "Identifier")
expect("row in", "Identifier")
expect(" in row", "Statement", 1)
expect("joined()", "Function")
expect('title={"}"}', "String", 7)
expect('literal {value}', "String", 9)
eq("Comment", group("htmlComment"), "HTML comment braces stay literal")
eq("", group("escaped"), "escaped body brace stays literal")
assert(group("javascript") ~= "Identifier", "JavaScript was highlighted as Swift")
assert(group("color:") ~= "Identifier", "CSS was highlighted as Swift")
checks = checks + 2

-- Filetypes follow the extension; Phoenix HEEx keeps its own filetype.
local function filetype(path)
  return vim.filetype.match({ filename = path })
end
eq("esw", filetype("login.esw"), "ESW extension")
eq("hesw", filetype("counter.live.hesw"), "HESW extension")
eq("heex", filetype("index.html.heex"), "Phoenix HEEx")
eq("html", filetype("index.html"), "ordinary HTML")

-- Changing filetypes and reloading syntax uses the standard buffer lifecycle.
buffer("<p><%= name %></p>")
vim.bo.filetype = "html"
vim.bo.filetype = "esw"
expect("<%= name", "Identifier", 4)
eq("esw", vim.b.current_syntax, "syntax reloaded")
print("ESW Neovim checks passed: " .. checks)
