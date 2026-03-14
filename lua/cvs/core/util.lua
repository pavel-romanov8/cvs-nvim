local uv = vim.uv or vim.loop

local M = {}

function M.notify(message, level)
  local config = require("cvs.config").get()

  if config.notifications.enabled == false then
    return
  end

  vim.notify(message, level or vim.log.levels.INFO, { title = "cvs.nvim" })
end

function M.normalize(path)
  if path == nil or path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

function M.path_join(...)
  return table.concat(vim.tbl_flatten({ ... }), "/")
end

function M.read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  return lines
end

function M.read_first_line(path)
  local lines = M.read_file(path)
  if not lines or lines[1] == nil then
    return nil
  end

  return vim.trim(lines[1])
end

function M.resolve_path(path)
  if path and path ~= "" then
    return M.normalize(vim.fn.fnamemodify(path, ":p"))
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" then
    return M.normalize(vim.fn.fnamemodify(current, ":p"))
  end

  local cwd = uv.cwd()
  return cwd and M.normalize(cwd) or nil
end

return M
