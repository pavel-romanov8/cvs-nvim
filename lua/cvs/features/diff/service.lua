local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local config = require("cvs.config")
local context = require("cvs.cvs.context")
local entries = require("cvs.cvs.entries")
local errors = require("cvs.core.errors")
local parse = require("cvs.features.diff.parse")
local runner = require("cvs.cvs.runner")
local util = require("cvs.core.util")
local uv = vim.uv or vim.loop

local M = {}
local next_request_id = 0
local pending = {}
local active = {}
local full_pending = {}

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
    source_modified = source_bufnr ~= nil and vim.bo[source_bufnr].modified or false,
    request = request,
    command = opts.stream and cmd.diff(request) or cmd.base(request),
    opts = opts,
  }
end

local function result_error(result, parsed)
  if result.stream_error then
    return errors.new("diff_failed", result.stream_error)
  end

  if result.code == nil or result.code > 1 or (result.signal or 0) ~= 0 then
    local message = result.stderr[1]
      or (parsed and parsed.messages and parsed.messages[1])
      or ("CVS diff exited with code %s"):format(tostring(result.code))
    return errors.new("diff_failed", message)
  end

  if parsed and parsed.error then
    return errors.new("diff_failed", parsed.error)
  end

  return nil
end

local function start_stream(view_state, callback)
  local limits = config.get().diff
  local parser = parse.new({
    max_bytes = limits.max_bytes,
    max_lines = limits.max_lines,
  })

  return runner.stream(view_state.command, {
    cwd = view_state.request.cwd,
  }, {
    on_stdout = function(chunk)
      parser:feed(chunk)
    end,
    on_complete = function(result)
      local parsed = parser:finish()
      local err = result_error(result, parsed)
      if err then
        callback(nil, err)
        return
      end

      view_state.loading = false
      view_state.result = result
      view_state.parsed = parsed
      callback(view_state, nil)
    end,
  })
end

local function read_file_prefix(path, max_bytes)
  local fd, open_err = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, nil, errors.new("diff_failed", tostring(open_err))
  end

  local stat, stat_err = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil, nil, errors.new("diff_failed", tostring(stat_err))
  end

  local byte_count = stat.size or 0
  local read_size = byte_count
  if max_bytes and max_bytes > 0 then
    read_size = math.min(read_size, max_bytes)
  end

  local contents = ""
  if read_size > 0 then
    local read_err
    contents, read_err = uv.fs_read(fd, read_size, 0)
    if not contents then
      uv.fs_close(fd)
      return nil, nil, errors.new("diff_failed", tostring(read_err))
    end
  end
  uv.fs_close(fd)

  local truncated = read_size < byte_count
  if truncated and not vim.endswith(contents, "\n") then
    contents = contents:match("^(.*\n)") or ""
  end

  return contents, {
    byte_count = read_size,
    truncated = truncated,
  }
end

local function collect_empty_base(opts, callback)
  local target_path, err = resolve_target_path(opts)
  if not target_path then
    callback(nil, err)
    return nil, err
  end

  local limits = config.get().diff
  local contents, read, read_err = read_file_prefix(target_path, limits.max_bytes)
  if not contents then
    callback(nil, read_err)
    return nil, read_err
  end

  local parsed
  if contents:find("\0", 1, true) then
    parsed = {
      lines = {},
      hunks = {},
      messages = { "Binary file contents cannot be shown inline." },
      binary = true,
    }
  else
    local parser = parse.new({
      max_lines = limits.max_lines,
    })
    parser:feed(vim.diff("", contents, {
      result_type = "unified",
    }))
    parsed = parser:finish()
    if #parsed.lines == 0 and not read.truncated then
      parsed.messages[1] = "New file is empty."
    end
  end

  parsed.byte_count = read.byte_count
  if read.truncated then
    parsed.truncated = true
    parsed.truncation_reason = "bytes"
  end

  local source_bufnr, source_win = detect_source(target_path, opts)
  local completed = {
    target_path = target_path,
    revision = "0",
    source_bufnr = source_bufnr,
    source_win = source_win,
    source_modified = source_bufnr ~= nil and vim.bo[source_bufnr].modified or false,
    parsed = parsed,
    opts = opts,
  }
  local process = {
    kill = function() end,
  }
  callback(completed, nil)
  return process, nil
end

function M.collect(opts, callback)
  opts = opts or {}
  if opts.empty_base then
    return collect_empty_base(opts, callback)
  end

  opts = vim.tbl_extend("force", opts or {}, { stream = true })
  local view_state, err = prepare(opts)
  if not view_state then
    callback(nil, err)
    return nil, err
  end

  local ok, process = pcall(start_stream, view_state, callback)
  if not ok then
    err = errors.new("diff_failed", tostring(process))
    callback(nil, err)
    return nil, err
  end

  return process, nil
end

local function open_stream(view_state, opts)
  local previous = active[view_state.target_path]
  if previous then
    runner.cancel(previous.process)
    if previous.bufnrs and previous.bufnrs[1] then
      require("cvs.features.diff.view").close(previous.bufnrs[1])
    end
  end

  view_state.loading = true
  local view = require("cvs.features.diff.view")
  local old_bufnr, new_bufnr = view.open(view_state, opts)

  next_request_id = next_request_id + 1
  local request = {
    id = next_request_id,
    bufnrs = { old_bufnr, new_bufnr },
  }
  pending[view_state.target_path] = request
  active[view_state.target_path] = request

  local ok, process = pcall(start_stream, view_state, function(completed, complete_err)
    if pending[view_state.target_path] ~= request then
      return
    end
    pending[view_state.target_path] = nil

    if complete_err then
      view_state.loading = false
      view_state.error = errors.to_string(complete_err)
      view.update(old_bufnr, view_state)
      util.notify(view_state.error, vim.log.levels.ERROR)
      return
    end

    view.update(old_bufnr, completed)
  end)

  if not ok then
    pending[view_state.target_path] = nil
    view_state.loading = false
    view_state.error = tostring(process)
    view.update(old_bufnr, view_state)
    util.notify(view_state.error, vim.log.levels.ERROR)
    return nil, old_bufnr, new_bufnr
  end

  request.process = process
  view.set_process(old_bufnr, process)
  return process, old_bufnr, new_bufnr
end

local function open_full(view_state)
  next_request_id = next_request_id + 1
  local request = {
    id = next_request_id,
  }

  local previous = full_pending[view_state.target_path]
  if previous then
    runner.cancel(previous.process)
  end
  full_pending[view_state.target_path] = request

  local ok, process = pcall(runner.run, view_state.command, {
    cwd = view_state.request.cwd,
  }, function(result)
    if full_pending[view_state.target_path] ~= request then
      return
    end
    full_pending[view_state.target_path] = nil

    if result.code ~= 0 then
      local message = result.stderr[1] or result.stdout[1] or ("CVS diff exited with code %d"):format(result.code)
      util.notify(errors.to_string(errors.new("diff_failed", message)), vim.log.levels.ERROR)
      return
    end

    view_state.result = result
    local opened, view_err = pcall(require("cvs.features.diff.full_view").open, view_state)
    if not opened then
      util.notify(errors.to_string(errors.new("diff_failed", tostring(view_err))), vim.log.levels.ERROR)
    end
  end)

  if not ok then
    full_pending[view_state.target_path] = nil
    local err = errors.new("diff_failed", tostring(process))
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  request.process = process
  return process
end

function M.open(opts)
  opts = opts or {}

  local view_state, err = prepare(opts)
  if not view_state then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  if opts.stream then
    return open_stream(view_state, opts)
  end
  return open_full(view_state)
end

function M.cancel(bufnr)
  for target_path, request in pairs(active) do
    if request.bufnrs and vim.tbl_contains(request.bufnrs, bufnr) then
      if pending[target_path] == request then
        pending[target_path] = nil
      end
      active[target_path] = nil
      runner.cancel(request.process)
      return true
    end
  end

  return false
end

M._prepare = prepare
M._resolve_target_path = resolve_target_path
M._result_error = result_error

return M
