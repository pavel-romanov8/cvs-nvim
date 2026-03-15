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

local function resolve_workspace_alias(path)
  if path == nil or path == "" then
    return path
  end

  if not vim.startswith(path, "@") then
    return path
  end

  local cwd = uv.cwd()
  if not cwd then
    return path
  end

  return M.path_join(cwd, path:sub(2))
end

local function resolve_explicit(path)
  if path == nil or path == "" then
    return nil
  end

  return M.normalize(vim.fn.fnamemodify(resolve_workspace_alias(path), ":p"))
end

function M.resolve_path(path)
  local resolved = resolve_explicit(path)
  if resolved then
    return resolved
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" then
    return M.normalize(vim.fn.fnamemodify(resolve_workspace_alias(current), ":p"))
  end

  local cwd = uv.cwd()
  return cwd and M.normalize(cwd) or nil
end

return M
