local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local parse = require("cvs.features.log.parse")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local util = require("cvs.core.util")
local window = require("cvs.ui.window")

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

  local inline = { revision = entry.revision, loading = true, lines = {} }
  view_state.inline = inline
  local token = {}
  attachment.preview_token = token
  require("cvs.features.log.buffer").update(bufnr, view_state)

  local command = cmd.base({ path = view_state.request.path, revision = entry.revision })
  local ok, process = pcall(runner.run, command, {
    cwd = view_state.request.cwd,
    timeout = false,
  }, function(result)
    local current = state.get_buffer(bufnr)
    if not current or current.preview_token ~= token then
      return
    end
    current.preview_process = nil
    inline.loading = false
    if result.code ~= 0 or (result.signal or 0) ~= 0 then
      inline.error = result.stderr[1] or ("CVS revision %s could not be loaded"):format(entry.revision)
    else
      local limit = require("cvs.config").get().ui.log.preview_lines
      local count = limit and limit > 0 and math.min(#result.stdout, limit) or #result.stdout
      for i = 1, count do
        if result.stdout[i]:find("\0", 1, true) then
          inline.lines = {}
          inline.error = "Binary file contents cannot be previewed."
          break
        end
        inline.lines[#inline.lines + 1] = result.stdout[i]
      end
      inline.truncated = #result.stdout > count
    end
    require("cvs.features.log.buffer").update(bufnr, view_state)
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

local function show_output(name, filetype, lines)
  local bufnr = ui_buffer.create({ name = name, filetype = filetype })
  ui_buffer.set_lines(bufnr, #lines > 0 and lines or { "(empty file)" })
  ui_buffer.lock(bufnr)
  ui_buffer.set_keymaps(bufnr, {
    { mode = "n", lhs = "q", rhs = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end, desc = "Close CVS revision view" },
  })
  return bufnr, window.open(bufnr, { kind = "split" })
end

function M.open_revision(bufnr)
  local view_state, entry = selected(bufnr)
  if not entry then
    return nil
  end
  local command = cmd.base({ path = view_state.request.path, revision = entry.revision })
  return runner.run(command, { cwd = view_state.request.cwd, timeout = false }, function(result)
    if result.code ~= 0 or (result.signal or 0) ~= 0 then
      util.notify(result.stderr[1] or ("CVS revision %s could not be loaded"):format(entry.revision), vim.log.levels.ERROR)
      return
    end
    local filetype = vim.filetype.match({ filename = view_state.target_path }) or "text"
    show_output(("cvs://revision/%s/%s"):format(view_state.target_path, entry.revision), filetype, result.stdout)
  end)
end

function M.diff_revision(bufnr)
  local view_state, entry = selected(bufnr)
  if not entry then
    return nil
  end
  local previous = parse.predecessor(entry.revision)
  if not previous then
    util.notify(("Revision %s has no predecessor."):format(entry.revision), vim.log.levels.WARN)
    return nil
  end
  local command = cmd.revision_diff({ path = view_state.request.path, from = previous, to = entry.revision })
  return runner.run(command, { cwd = view_state.request.cwd, timeout = false }, function(result)
    -- cvs diff returns 1 when revisions differ; 2+ indicates failure.
    if result.code > 1 or (result.signal or 0) ~= 0 or (#result.stdout == 0 and #result.stderr > 0) then
      util.notify(result.stderr[1] or ("CVS diff failed with code %d"):format(result.code), vim.log.levels.ERROR)
      return
    end
    show_output(("cvs://revision-diff/%s/%s..%s"):format(view_state.target_path, previous, entry.revision),
      "diff", #result.stdout > 0 and result.stdout or { "No differences." })
  end)
end

return M
