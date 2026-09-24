local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local parse = require("cvs.features.log.parse")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local util = require("cvs.core.util")
local revision_diff = require("cvs.features.log.diff")
local diff_buffer = require("cvs.features.log.diff_buffer")
local source_syntax = require("cvs.features.diff.source_syntax")

local M = {}

local function cancel_preview(attachment)
  attachment.preview_token = nil
  if attachment.preview_process then
    runner.cancel(attachment.preview_process)
    attachment.preview_process = nil
  end
end

local function prepare(opts)
  local path = util.resolve_path(opts.path)
  if not path then
    return nil, errors.new("path_missing", "could not resolve a file for CVS log")
  end
  if vim.fn.isdirectory(path) == 1 then
    return nil, errors.new("log_requires_file", ("CVS log requires a file path, got directory: %s"):format(path))
  end
  local workspace, err = context.detect(path)
  if not workspace then
    return nil, err
  end
  local caps = capabilities.detect()
  if not caps.executable then
    return nil, errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
  end
  local request = { cwd = vim.fs.dirname(path), path = vim.fs.basename(path) }
  return {
    workspace = workspace,
    target_path = path,
    request = request,
    command = cmd.log(request),
    loading = true,
    parsed = { entries = {}, header = {} },
  }
end

local function load(bufnr, view_state)
  local attachment = state.get_buffer(bufnr)
  if not attachment then
    return nil
  end
  if attachment.process then
    runner.cancel(attachment.process)
  end
  cancel_preview(attachment)
  view_state.inline = nil
  local token = {}
  attachment.token = token
  view_state.loading = true
  view_state.error = nil
  require("cvs.features.log.buffer").update(bufnr, view_state)

  local ok, process = pcall(runner.run, view_state.command, {
    cwd = view_state.request.cwd,
    timeout = false,
  }, function(result)
    local current = state.get_buffer(bufnr)
    if not current or current.token ~= token then
      return
    end
    current.process = nil
    view_state.loading = false
    if result.code ~= 0 or (result.signal or 0) ~= 0 then
      view_state.error = result.stderr[1] or result.stdout[1] or ("CVS log exited with code %d"):format(result.code)
    else
      view_state.parsed = parse.parse(result.stdout)
    end
    require("cvs.features.log.buffer").update(bufnr, view_state)
  end)
  if not ok then
    view_state.loading = false
    view_state.error = tostring(process)
    require("cvs.features.log.buffer").update(bufnr, view_state)
    return nil
  end
  attachment.process = process
  return process
end

function M.open(opts)
  opts = opts or {}
  local view_state, err = prepare(opts)
  if not view_state then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end
  local bufnr, winid = require("cvs.features.log.buffer").open(view_state, opts)
  return bufnr, winid, load(bufnr, view_state)
end

function M.refresh(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "log" then
    return nil
  end
  return load(bufnr, attachment.view_state)
end

local function selected(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "log" then
    return nil, nil
  end
  return attachment.view_state, require("cvs.features.log.buffer").current(bufnr)
end

function M.toggle_preview(bufnr)
  local view_state, entry = selected(bufnr)
  if not entry then
    return nil
  end
  local attachment = state.get_buffer(bufnr)
  cancel_preview(attachment)
  if view_state.inline and view_state.inline.revision == entry.revision then
    view_state.inline = nil
    require("cvs.features.log.buffer").update(bufnr, view_state)
    return false
  end

  local inline = { revision = entry.revision, loading = true, lines = {}, messages = {} }
  view_state.inline = inline
  local token = {}
  attachment.preview_token = token
  require("cvs.features.log.buffer").update(bufnr, view_state)

  local ok, process = pcall(revision_diff.collect, view_state.request, entry.revision, function(diff, err)
    local current = state.get_buffer(bufnr)
    if not current or current.preview_token ~= token then
      return
    end
    current.preview_process = nil
    inline.loading = false
    if err then
      inline.error = err
    else
      local limit = require("cvs.config").get().ui.log.preview_lines
      local count = limit and limit > 0 and math.min(#diff.parsed.lines, limit) or #diff.parsed.lines
      for i = 1, count do
        inline.lines[#inline.lines + 1] = diff.parsed.lines[i]
      end
      inline.messages = diff.parsed.messages
      inline.truncated = diff.parsed.truncated or #diff.parsed.lines > count
    end
    require("cvs.features.log.buffer").update(bufnr, view_state)
    if not err and require("cvs.config").get().diff.syntax_highlighting ~= false then
      vim.schedule(function()
        local latest = state.get_buffer(bufnr)
        if not latest or latest.preview_token ~= token then return end
        inline.syntax = source_syntax.captures(inline.lines, view_state.target_path)
        require("cvs.features.log.buffer").update(bufnr, view_state)
      end)
    end
  end)
  if not ok then
    inline.loading = false
    inline.error = tostring(process)
    require("cvs.features.log.buffer").update(bufnr, view_state)
    return nil
  end
  attachment.preview_process = process
  return true
end

function M.open_revision(bufnr)
  local view_state, entry = selected(bufnr)
  if not entry then
    return nil
  end
  local view = {
    path = view_state.target_path,
    from = parse.predecessor(entry.revision),
    to = entry.revision,
    loading = true,
  }
  local full_bufnr, winid = diff_buffer.open(view)
  local ok, process = pcall(revision_diff.collect, view_state.request, entry.revision, function(diff, err)
    if not vim.api.nvim_buf_is_valid(full_bufnr) then
      return
    end
    diff_buffer.clear_process(full_bufnr)
    view.loading = false
    view.error = err
    view.parsed = diff and diff.parsed
    diff_buffer.update(full_bufnr, view)
  end)
  if not ok then
    view.loading = false
    view.error = tostring(process)
    diff_buffer.update(full_bufnr, view)
  else
    diff_buffer.set_process(full_bufnr, process)
  end
  return full_bufnr, winid
end

M.diff_revision = M.open_revision

return M
