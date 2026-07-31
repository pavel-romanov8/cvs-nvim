local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local entries = require("cvs.cvs.entries")
local errors = require("cvs.core.errors")
local runner = require("cvs.cvs.runner")
local util = require("cvs.core.util")

local M = {}
local next_request_id = 0
local pending = {}

local function resolve_target_path(opts)
  local path = util.resolve_path(opts.path)
  if not path then
    return nil, errors.new("path_missing", "could not resolve a file for CVS diff")
  end

  if vim.fn.isdirectory(path) == 1 then
    return nil, errors.new("diff_requires_file", ("CVS diff requires a file path, got directory: %s"):format(path))
  end

  if vim.fn.filereadable(path) ~= 1 then
    return nil, errors.new("diff_requires_file", ("CVS diff requires a readable file: %s"):format(path))
  end

  return path
end

local function detect_source(target_path, opts)
  if opts.source_bufnr and vim.api.nvim_buf_is_valid(opts.source_bufnr) then
    return opts.source_bufnr, opts.source_win
  end

  local current = vim.api.nvim_get_current_buf()
  if util.normalize(vim.api.nvim_buf_get_name(current)) == target_path then
    return current, vim.api.nvim_get_current_win()
  end

  local bufnr = vim.fn.bufnr(target_path)
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr, nil
  end

  return nil, nil
end

local function prepare(opts)
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

  local revision = entries.working_revision(target_path)
  if not revision then
    return nil, errors.new(
      "base_revision_missing",
      ("no checked-out CVS revision found for %s"):format(target_path)
    )
  end

  local source_bufnr, source_win = detect_source(target_path, opts)
  local request = {
    cwd = vim.fs.dirname(target_path),
    path = vim.fs.basename(target_path),
    revision = revision,
  }

  return {
    workspace = workspace,
    target_path = target_path,
    revision = revision,
    source_bufnr = source_bufnr,
    source_win = source_win,
    request = request,
    command = cmd.base(request),
    opts = opts,
  }
end

function M.open(opts)
  opts = opts or {}

  local view_state, err = prepare(opts)
  if not view_state then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  next_request_id = next_request_id + 1
  local request_id = next_request_id
  pending[view_state.target_path] = request_id

  return runner.run(view_state.command, {
    cwd = view_state.request.cwd,
  }, function(result)
    if pending[view_state.target_path] ~= request_id then
      return
    end
    pending[view_state.target_path] = nil

    if result.code ~= 0 then
      local message = result.stderr[1] or result.stdout[1] or ("CVS diff exited with code %d"):format(result.code)
      util.notify(errors.to_string(errors.new("diff_failed", message)), vim.log.levels.ERROR)
      return
    end

    view_state.result = result
    require("cvs.features.diff.view").open(view_state)
  end)
end

M._prepare = prepare
M._resolve_target_path = resolve_target_path

return M
