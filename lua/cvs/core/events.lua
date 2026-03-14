local M = {}

function M.emit(pattern, data)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    modeline = false,
    data = data,
  })
end

return M
