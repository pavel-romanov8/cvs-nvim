local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local parse = require("cvs.features.annotate.parse")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local util = require("cvs.core.util")

local M = {}

local function resolve_target_path(opts)
  local path = util.resolve_path(opts.path)
  if not path then
    return nil, errors.new("path_missing", "could not resolve a file for CVS annotate")
  end

  if vim.fn.isdirectory(path) == 1 then
    return nil, errors.new("annotate_requires_file", ("CVS annotate requires a file path, got directory: %s"):format(path))
  end

  if vim.fn.filereadable(path) ~= 1 then
    return nil, errors.new("annotate_requires_file", ("CVS annotate requires a readable file: %s"):format(path))
  end

  return path
end

local function detect_source_bufnr(target_path, opts)
  if opts.source_bufnr and vim.api.nvim_buf_is_valid(opts.source_bufnr) then
    return opts.source_bufnr
  end

  local current = vim.api.nvim_get_current_buf()
  local current_name = util.normalize(vim.api.nvim_buf_get_name(current))
  if current_name == target_path then
    return current
  end

  return nil
end

local function find_attachment(arg)
  local data = state.get_buffer(arg)
  if data and data.kind == "annotate" then
    return arg, data
  end

  return state.find_buffer(function(_, entry)
    return entry.kind == "annotate" and entry.source_bufnr == arg
  end)
end

local function collect(opts)
  local target_path, err = resolve_target_path(opts)
  if not target_path then
    return nil, err
  end

  local workspace, context_err = context.detect(target_path)
  if not workspace then
    return nil, context_err
  end

  local caps = capabilities.detect()
  if not caps.executable then
    return nil, errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
  end

  local command = cmd.annotate(vim.tbl_extend("force", opts, { path = target_path }))
  local result = runner.run(command, {
    cwd = workspace.root_dir,
  })
  local parsed = parse.parse(result.stdout)

  if result.code ~= 0 and #parsed.entries == 0 then
    local message = result.stderr[1] or ("CVS annotate exited with code %d"):format(result.code)
    return nil, errors.new("annotate_failed", message, {
      code = result.code,
      path = target_path,
    })
  end

  local source_bufnr = detect_source_bufnr(target_path, opts)
  local source_win = opts.source_win
  if not source_win and source_bufnr and vim.api.nvim_get_current_buf() == source_bufnr then
    source_win = vim.api.nvim_get_current_win()
  end

  return {
    workspace = workspace,
    target_path = target_path,
    command = command,
    result = result,
    parsed = parsed,
    source_bufnr = source_bufnr,
    source_win = source_win,
    stale = source_bufnr and vim.bo[source_bufnr].modified or false,
    opts = opts,
  }
end

function M.open(opts)
  opts = opts or {}

  local view_state, err = collect(opts)
  if not view_state then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  if view_state.source_bufnr then
    local bufnr = find_attachment(view_state.source_bufnr)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      return require("cvs.features.annotate.buffer").update(bufnr, view_state)
    end
  end

  return require("cvs.features.annotate.buffer").open(view_state, opts)
end

function M.refresh(arg)
  local bufnr, attachment = find_attachment(arg)
  if not bufnr or not attachment then
    return nil
  end

  local view_state, err = collect(vim.tbl_extend("force", {}, attachment.opts or {}, {
    path = attachment.target_path,
    source_bufnr = attachment.source_bufnr,
    source_win = attachment.source_win,
  }))

  if not view_state then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return require("cvs.features.annotate.buffer").update(bufnr, view_state)
end

return M
