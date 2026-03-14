local M = {}

function M.close(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.refresh(path)
  require("cvs.features.status.service").open({ path = path })
end

return M
