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
local uv = vim.uv or vim.loop

local function cancel_preview(attachment)
  attachment.preview_token = nil
  if attachment.preview_process then
    runner.cancel(attachment.preview_process)
    attachment.preview_process = nil
  end
end

local function relative_to(root, path)
  if path == root then
    return "."
  end
  local prefix = root .. "/"
  if vim.startswith(path, prefix) then
    return path:sub(#prefix + 1)
  end
  return path
end

local function context_path(opts)
  if opts.path and opts.path ~= "" then
    if opts.path == "%" then
      local current = vim.api.nvim_buf_get_name(0)
      return current ~= "" and current or nil
    end
    return opts.path
  end

  local attachment = state.get_buffer(vim.api.nvim_get_current_buf())
  if attachment then
    if attachment.target_path then
      return attachment.target_path
    end
    local attached_view = attachment.view_state
    if attached_view then
      if attached_view.target_path then
        return attached_view.target_path
      end
      if attached_view.scope_path then
        return attached_view.scope_path
      end
      if attached_view.opts and attached_view.opts.path then
        return attached_view.opts.path
      end
      if attached_view.workspace then
        return attached_view.workspace.root_dir
      end
    end
    if attachment.root_dir then
      return attachment.root_dir
    end
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" and (vim.fn.isdirectory(current) == 1 or vim.bo.buftype == "") then
    return current
  end
  return uv.cwd()
end

local function prepare(opts)
  local path = util.resolve_path(context_path(opts))
  if not path then
    return nil, errors.new("path_missing", "could not resolve a file or directory for CVS log")
  end
  local workspace, err = context.detect(path)
  if not workspace then
    return nil, err
  end
  if opts.force then
    path = workspace.root_dir
  end
  local caps = capabilities.detect()
  if not caps.executable then
    return nil, errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
  end

  local is_directory = vim.fn.isdirectory(path) == 1
  if is_directory and (not workspace.repository or workspace.repository == "") then
    return nil, errors.new("repository_missing", "CVS/Repository is required for directory history")
  end
  local request
  local command
  local parsed
  local repository_scope
  if is_directory then
    local relative_scope = relative_to(workspace.root_dir, path)
    repository_scope = workspace.repository
    if relative_scope ~= "." then
      repository_scope = util.path_join(repository_scope, relative_scope)
    end
    request = { cwd = workspace.root_dir, path = repository_scope }
    command = cmd.rlog(request)
    parsed = { files = {}, commits = {} }
  else
    request = { cwd = vim.fs.dirname(path), path = vim.fs.basename(path) }
    command = cmd.log(request)
    parsed = { entries = {}, header = {} }
  end

  return {
    workspace = workspace,
    scope_kind = is_directory and "directory" or "file",
    scope_path = path,
    scope_label = relative_to(workspace.root_dir, path),
    repository_scope = repository_scope,
    target_path = is_directory and nil or path,
    request = request,
    command = command,
    loading = true,
    parsed = parsed,
    expanded = {},
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
      if view_state.scope_kind == "directory" then
        view_state.parsed = parse.parse_scope(result.stdout, {
          scope_path = view_state.scope_path,
          logging_prefix = view_state.repository_scope,
        })
        for _, commit in ipairs(view_state.parsed.commits) do
          for _, file in ipairs(commit.files) do
            file.path = relative_to(view_state.workspace.root_dir, file.absolute_path)
          end
        end
      else
        view_state.parsed = parse.parse(result.stdout)
        for _, entry in ipairs(view_state.parsed.entries) do
          entry.path = relative_to(view_state.workspace.root_dir, view_state.target_path)
          entry.absolute_path = view_state.target_path
        end
      end
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

local function selected_entry(item)
  if not item then
    return nil
  end
  if item.kind == "change" then
    return item.entry
  end
  if item.kind == "commit" then
    return nil
  end
  return item
end

local function selected_commit(item)
  if not item then
    return nil
  end
  if item.kind == "commit" or item.kind == "change" then
    return item.commit
  end
  return item.commit_id and {
    id = item.commit_id,
    date = item.date,
    author = item.author,
    message = item.message,
    files = { item },
  } or nil
end

local function request_for_entry(view_state, entry)
  local path = entry.absolute_path or view_state.target_path
  return { cwd = vim.fs.dirname(path), path = vim.fs.basename(path) }
end

function M.toggle_preview(bufnr)
  local view_state, item = selected(bufnr)
  if not item then
    return nil
  end

  if view_state.scope_kind == "directory" then
    local commit = selected_commit(item)
    if not commit then
      return nil
    end
    view_state.expanded = view_state.expanded or {}
    view_state.expanded[commit.key] = not view_state.expanded[commit.key]
    require("cvs.features.log.buffer").update(bufnr, view_state)
    return view_state.expanded[commit.key]
  end

  local entry = selected_entry(item)
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
  local view_state, item = selected(bufnr)
  if not item then
    return nil
  end
  if item.kind == "commit" then
    return M.toggle_preview(bufnr)
  end
  local entry = selected_entry(item)
  if not entry then
    return nil
  end
  local target_path = entry.absolute_path or view_state.target_path
  local view = {
    path = target_path,
    from = parse.predecessor(entry.revision),
    to = entry.revision,
    loading = true,
  }
  local full_bufnr, winid = diff_buffer.open(view)
  local ok, process = pcall(revision_diff.collect, request_for_entry(view_state, entry), entry.revision, function(diff, err)
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

function M.copy_commit_id(bufnr)
  local _, item = selected(bufnr)
  local commit = selected_commit(item)
  if not commit or not commit.id then
    util.notify("This revision has no CVS commit ID.", vim.log.levels.WARN)
    return nil
  end
  vim.fn.setreg('"', commit.id)
  util.notify(("Copied CVS commit ID %s."):format(commit.id))
  return commit.id
end

function M.revert_commit(bufnr)
  local view_state, item = selected(bufnr)
  local commit = selected_commit(item)
  if not commit or not commit.id then
    util.notify("This revision has no CVS commit ID to revert.", vim.log.levels.WARN)
    return nil
  end
  return require("cvs.features.revert.service").open({
    workspace = view_state.workspace,
    commit_id = commit.id,
    seed = commit,
  })
end

M.diff_revision = M.open_revision
M._prepare = prepare
M._relative_to = relative_to

return M
