local config = require("cvs.config")

local M = {}

local function base()
  local cfg = config.get().cvs
  local cmd = { cfg.bin }

  vim.list_extend(cmd, cfg.global_args or {})

  return cmd
end

local function add_files(cmd, opts)
  local files = opts.files or {}
  if opts.path then
    files = vim.deepcopy(files)
    files[#files + 1] = opts.path
  end

  vim.list_extend(cmd, files)
  return cmd
end

function M.status(opts)
  local cmd = base()
  vim.list_extend(cmd, { "-nq", "update" })
  return add_files(cmd, opts or {})
end

function M.update(opts)
  local cmd = base()
  vim.list_extend(cmd, { "-q", "update" })
  return add_files(cmd, opts or {})
end

function M.commit(opts)
  local cmd = base()
  table.insert(cmd, "commit")

  if opts and opts.message then
    vim.list_extend(cmd, { "-m", opts.message })
  end

  return add_files(cmd, opts or {})
end

function M.diff(opts)
  local cmd = base()
  vim.list_extend(cmd, { "diff", "-u" })
  return add_files(cmd, opts or {})
end

function M.log(opts)
  local cmd = base()
  table.insert(cmd, "log")
  return add_files(cmd, opts or {})
end

function M.annotate(opts)
  local cmd = base()
  table.insert(cmd, "annotate")
  return add_files(cmd, opts or {})
end

function M.add(opts)
  local cmd = base()
  table.insert(cmd, "add")
  return add_files(cmd, opts or {})
end

function M.remove(opts)
  local cmd = base()
  vim.list_extend(cmd, { "remove", "-f" })
  return add_files(cmd, opts or {})
end

return M
