local M = {}

function M.close(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.refresh(bufnr)
  return require("cvs.features.status.service").refresh(bufnr)
end

function M.open_current(bufnr)
  return require("cvs.features.status.service").open_current(bufnr)
end

function M.add_current(bufnr)
  return require("cvs.features.status.service").add_current(bufnr)
end

function M.remove_current(bufnr)
  return require("cvs.features.status.service").remove_current(bufnr)
end

return M
