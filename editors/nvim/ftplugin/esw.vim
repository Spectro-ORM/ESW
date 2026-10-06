if exists('b:did_ftplugin')
  finish
endif
runtime! ftplugin/html.vim
setlocal commentstring=<%!--\ %s\ --%>
setlocal comments=
let b:undo_ftplugin .= ' | setlocal commentstring< comments<'

" A deprecated .heex buffer may previously have been opened as Phoenix HEEx.
lua pcall(vim.treesitter.stop, vim.api.nvim_get_current_buf())
