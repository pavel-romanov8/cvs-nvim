local M = {}

function M.close(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.refresh(bufnr)
  return require("cvs.features.status.service").refresh(bufnr)
end

function M.open_current(bufnr, kind)
  return require("cvs.features.status.service").open_current(bufnr, kind)
end

function M.diff_current(bufnr)
  return require("cvs.features.status.service").diff_current(bufnr)
end

function M.add_current(bufnr, start_row, end_row)
  return require("cvs.features.status.service").add_current(bufnr, start_row, end_row)
end

function M.add_binary(bufnr, start_row, end_row)
  return require("cvs.features.status.service").add_binary(bufnr, start_row, end_row)
end

function M.remove_current(bufnr)
  return require("cvs.features.status.service").remove_current(bufnr)
end

function M.discard_current(bufnr, start_row, end_row)
  return require("cvs.features.status.service").discard_current(bufnr, start_row, end_row)
end

function M.toggle_inline_diff(bufnr)
  return require("cvs.features.status.service").toggle_inline_diff(bufnr)
end

function M.toggle_selection(bufnr, start_row, end_row)
  return require("cvs.features.status.service").toggle_selection(bufnr, start_row, end_row)
end

function M.commit_selected(bufnr)
  return require("cvs.features.status.service").commit_selected(bufnr)
end

return M
