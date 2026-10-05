local M = {}

-- Filetype detection only reads manifests; it never evaluates project code.
-- Stop at the nearest project so an Elixir app nested in a Swift checkout
-- retains its normal HEEx support.
function M.heex_filetype(path)
  local manifest = vim.fs.find({ "mix.exs", "Package.swift" }, {
    path = vim.fs.dirname(path),
    upward = true,
    type = "file",
    limit = 1,
  })[1]
  if not manifest or vim.fs.basename(manifest) ~= "Package.swift" then
    return
  end
  local ok, lines = pcall(vim.fn.readfile, manifest)
  if not ok then
    return
  end
  local source = table.concat(lines, "\n")
  if source:find('"ESW"') or source:find('"ESWLive"') or source:find('"ESWBuildPlugin"') then
    return "eswheex"
  end
end

return M
