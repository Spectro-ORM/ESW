if vim.g.loaded_esw then
  return
end
vim.g.loaded_esw = true

vim.filetype.add({
  extension = { esw = "esw" },
  pattern = {
    [".*%.heex"] = { require("esw").heex_filetype, { priority = 10 } },
  },
})
