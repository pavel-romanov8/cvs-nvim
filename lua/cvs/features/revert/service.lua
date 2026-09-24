local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local entries = require("cvs.cvs.entries")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local status_parse = require("cvs.features.status.parse")
local log_parse = require("cvs.features.log.parse")
local util = require("cvs.core.util")

local M = {}
local uv = vim.uv or vim.loop

local function update(bufnr, view_state)
  require("cvs.features.revert.buffer").update(bufnr, view_state)
end

local function path_is_modified_in_buffer(path)
  local normalized = vim.fs.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr)
      and vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == normalized
      and vim.bo[bufnr].modified
    then
      return true
    end
  end
  return false
end

local function make_items(commit)
  local items = {}
  for _, revision in ipairs(commit.files or {}) do
    local predecessor = log_parse.predecessor(revision.revision)
    local action
    if revision.state == "dead" then
      action = "restore"
    elseif not predecessor then
      action = "remove"
    else
      action = "reverse_merge"
    end
    items[#items + 1] = {
      path = revision.path,
      absolute_path = revision.absolute_path,
      revision = revision.revision,
      predecessor = predecessor,
      state = revision.state,
      action = action,
      current_revision = entries.working_revision(revision.absolute_path),
    }
  end
  return items
end

local function revision_branch(revision)
  local parts = vim.split(revision or "", ".", { plain = true })
  if #parts <= 2 then
    return "trunk"
  end
  table.remove(parts)
  return table.concat(parts, ".")
end

local function check_working_copy(bufnr, view_state, on_ready)
  view_state.phase = "checking"
  view_state.error = nil
  view_state.blockers = {}
  update(bufnr, view_state)

  local files = {}
  for _, item in ipairs(view_state.items) do
    item.current_revision = entries.working_revision(item.absolute_path)
    if vim.fn.isdirectory(vim.fs.dirname(item.absolute_path) .. "/CVS") ~= 1 then
      view_state.blockers[#view_state.blockers + 1] = item.path .. ": parent directory is not checked out"
    end
    if item.action ~= "restore" then
      files[#files + 1] = item.path
      if not item.current_revision then
        view_state.blockers[#view_state.blockers + 1] = item.path .. ": no checked-out CVS revision was found"
      elseif revision_branch(item.current_revision) ~= revision_branch(item.revision) then
        view_state.blockers[#view_state.blockers + 1] = item.path .. ": checked out on a different CVS branch"
      end
    elseif uv.fs_stat(item.absolute_path) then
      view_state.blockers[#view_state.blockers + 1] = item.path .. ": removed repository file already exists locally"
    end
    if path_is_modified_in_buffer(item.absolute_path) then
      view_state.blockers[#view_state.blockers + 1] = item.path .. ": buffer has unsaved changes"
    end
  end

  if #view_state.blockers > 0 then
    view_state.phase = "blocked"
    update(bufnr, view_state)
    return
  end

  if #files == 0 then
    view_state.phase = "ready"
    update(bufnr, view_state)
    if on_ready then on_ready() end
    return
  end

  local attachment = state.get_buffer(bufnr)
  local process
  process = runner.run(cmd.status({ files = files }), {
    cwd = view_state.workspace.root_dir,
  }, function(result)
    local current = state.get_buffer(bufnr)
    if not current or current.process ~= process then
      return
    end
    current.process = nil
    if result.code ~= 0 or (result.signal or 0) ~= 0 then
      view_state.error = result.stderr[1] or result.stdout[1]
        or ("CVS preflight exited with code %d"):format(result.code)
      view_state.phase = "blocked"
      update(bufnr, view_state)
      return
    end

    local parsed = status_parse.parse(result.stdout)
    for _, file in ipairs(parsed.files) do
      view_state.blockers[#view_state.blockers + 1] = ("%s: CVS reports %s"):format(file.path, file.status)
    end
    if #view_state.blockers > 0 then
      view_state.phase = "blocked"
    else
      view_state.phase = "ready"
    end
    update(bufnr, view_state)
    if view_state.phase == "ready" and on_ready then on_ready() end
  end)
  attachment.process = process
end

local function discover(bufnr, view_state)
  local attachment = state.get_buffer(bufnr)
  local process
  process = runner.run(cmd.rlog({ path = view_state.workspace.repository }), {
    cwd = view_state.workspace.root_dir,
    timeout = false,
  }, function(result)
    local current = state.get_buffer(bufnr)
    if not current or current.process ~= process then
      return
    end
    current.process = nil
    if result.code ~= 0 or (result.signal or 0) ~= 0 then
      view_state.error = result.stderr[1] or result.stdout[1]
        or ("CVS log exited with code %d"):format(result.code)
      view_state.phase = "blocked"
      update(bufnr, view_state)
      return
    end

    local parsed = log_parse.parse_scope(result.stdout, {
      scope_path = view_state.workspace.root_dir,
      logging_prefix = view_state.workspace.repository,
    })
    local commit = log_parse.find_commit(parsed, view_state.commit_id)
    if not commit then
      view_state.error = ("commit ID %s was not found in this workspace"):format(view_state.commit_id)
      view_state.phase = "blocked"
      update(bufnr, view_state)
      return
    end

    view_state.commit = commit
    view_state.items = make_items(commit)
    if #view_state.items == 0 then
      view_state.error = "the commit contains no files in this workspace"
      view_state.phase = "blocked"
      update(bufnr, view_state)
      return
    end
    check_working_copy(bufnr, view_state)
  end)
  attachment.process = process
  return process
end

function M.open(opts)
  opts = opts or {}
  if not opts.commit_id or opts.commit_id == "" then
    local err = errors.new("commit_id_missing", "a CVS commit ID is required")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local workspace = opts.workspace
  local err
  if not workspace then
    local attachment = state.get_buffer(vim.api.nvim_get_current_buf())
    local attached_view = attachment and attachment.view_state
    workspace = attached_view and attached_view.workspace or nil
  end
  if not workspace then
    local detect_path = opts.path
    if not detect_path then
      local current = vim.api.nvim_buf_get_name(0)
      if current ~= "" and (vim.fn.isdirectory(current) == 1 or vim.bo.buftype == "") then
        detect_path = current
      else
        detect_path = uv.cwd()
      end
    end
    workspace, err = context.detect(detect_path)
  end
  if not workspace then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end
  if not workspace.repository or workspace.repository == "" then
    err = errors.new("repository_missing", "CVS/Repository is required to discover a complete commit")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end
  local caps = capabilities.detect()
  if not caps.executable then
    err = errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local view_state = {
    workspace = workspace,
    commit_id = opts.commit_id,
    commit = opts.seed,
    phase = "loading",
    items = {},
    blockers = {},
    messages = {},
  }
  local bufnr, winid = require("cvs.features.revert.buffer").open(view_state, opts)
  return bufnr, winid, discover(bufnr, view_state)
end

local function command_failed(result)
  if result.code ~= 0 or (result.signal or 0) ~= 0 then
    return result.stderr[1] or result.stdout[1] or ("CVS exited with code %d"):format(result.code)
  end
  for _, line in ipairs(result.stdout or {}) do
    if line:match("^C%s+") then
      return "CVS reported a merge conflict: " .. line
    end
  end
  return nil
end

local function write_revision(item, result)
  if table.concat(result.stdout or {}, "\n"):find("\0", 1, true) then
    return nil, "cannot automatically restore a removed binary file"
  end
  vim.fn.mkdir(vim.fs.dirname(item.absolute_path), "p")
  local flags = result.stdout_ends_with_newline and "" or "b"
  local ok, write_err = pcall(vim.fn.writefile, result.stdout or {}, item.absolute_path, flags)
  if not ok then
    return nil, tostring(write_err)
  end
  return true
end

local function run_item(view_state, item, callback)
  if item.action == "reverse_merge" then
    local command = cmd.reverse_merge({ from = item.revision, to = item.predecessor, path = item.path })
    return runner.run(command, { cwd = view_state.workspace.root_dir }, function(result)
      callback(command_failed(result))
    end)
  elseif item.action == "remove" then
    local command = cmd.remove({ path = item.path })
    return runner.run(command, { cwd = view_state.workspace.root_dir }, function(result)
      callback(command_failed(result))
    end)
  elseif item.action == "restore" then
    if not item.predecessor then
      callback("removed revision has no predecessor to restore")
      return nil
    end
    local print_command = cmd.base({ path = item.path, revision = item.predecessor })
    return runner.run(print_command, { cwd = view_state.workspace.root_dir }, function(result)
      local failure = command_failed(result)
      if failure then
        callback(failure)
        return
      end
      local ok, write_err = write_revision(item, result)
      if not ok then
        callback(write_err)
        return
      end
      local add_command = cmd.add({ path = item.path })
      runner.run(add_command, { cwd = view_state.workspace.root_dir }, function(add_result)
        callback(command_failed(add_result))
      end)
    end)
  end
  callback("unsupported revert action for " .. item.path)
  return nil
end

function M.preview(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "revert" then
    return nil
  end
  local item = require("cvs.features.revert.buffer").current(bufnr)
  if not item then
    util.notify("Move to an affected file to preview its reverse diff.", vim.log.levels.WARN)
    return nil
  end

  local view = {
    path = item.absolute_path,
    from = item.action == "restore" and "(empty)" or item.revision,
    to = item.action == "restore" and item.predecessor or (item.predecessor or "(empty)"),
    loading = true,
  }
  local diff_buffer = require("cvs.features.log.diff_buffer")
  local full_bufnr, winid = diff_buffer.open(view)
  local request = { cwd = vim.fs.dirname(item.absolute_path), path = vim.fs.basename(item.absolute_path) }
  local collector = require("cvs.features.log.diff")
  local function complete(diff, err)
    if not vim.api.nvim_buf_is_valid(full_bufnr) then
      return
    end
    diff_buffer.clear_process(full_bufnr)
    view.loading = false
    view.error = err
    view.parsed = diff and diff.parsed
    diff_buffer.update(full_bufnr, view)
  end
  local process
  if item.action == "restore" then
    process = collector.collect_restore(request, item.predecessor, complete)
  else
    process = collector.collect_reverse(request, item.revision, item.predecessor, complete)
  end
  diff_buffer.set_process(full_bufnr, process)
  return full_bufnr, winid
end

local function commit_message(view_state)
  local subject = "CVS commit " .. view_state.commit_id
  for _, line in ipairs((view_state.commit and view_state.commit.message) or {}) do
    if line ~= "" then
      subject = line
      break
    end
  end
  local lines = {
    ('Revert "%s"'):format(subject),
    "",
    "Reverts CVS commit " .. view_state.commit_id .. ".",
    "",
  }
  if view_state.commit and view_state.commit.author then
    lines[#lines + 1] = "Original author: " .. view_state.commit.author
  end
  if view_state.commit and view_state.commit.date then
    lines[#lines + 1] = "Original date: " .. view_state.commit.date
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Affected revisions:"
  for _, item in ipairs(view_state.items) do
    lines[#lines + 1] = ("  %s: %s"):format(item.path, item.revision)
  end
  return lines
end

local function open_commit(view_state)
  local files = {}
  for _, item in ipairs(view_state.items) do
    files[#files + 1] = item.path
  end
  return require("cvs.features.commit.service").open({
    workspace = view_state.workspace,
    files = files,
    message_lines = commit_message(view_state),
  })
end

local function apply_ready(bufnr, view_state, open_after)
  view_state.phase = "applying"
  view_state.messages = { "Applying reverse changes to the working copy..." }
  update(bufnr, view_state)

  queue.enqueue(view_state.workspace.root_dir, function(done)
    local index = 1
    local function step()
      local item = view_state.items[index]
      if not item then
        view_state.phase = "applied"
        view_state.messages = { "Revert applied locally. Review the changes before committing." }
        state.invalidate_status_cache(view_state.workspace.root_dir)
        events.emit("CvsChanged", {
          root_dir = view_state.workspace.root_dir,
          operation = "revert-apply",
          commit_id = view_state.commit_id,
        })
        update(bufnr, view_state)
        done()
        if open_after then
          open_commit(view_state)
        end
        return
      end
      view_state.messages = { ("Applying %d/%d: %s"):format(index, #view_state.items, item.path) }
      update(bufnr, view_state)
      run_item(view_state, item, function(failure)
        if failure then
          view_state.phase = "blocked"
          view_state.error = ("%s: %s. Earlier files may already be modified."):format(item.path, failure)
          view_state.messages = {}
          state.invalidate_status_cache(view_state.workspace.root_dir)
          update(bufnr, view_state)
          done()
          return
        end
        index = index + 1
        step()
      end)
    end
    step()
  end, function(queue_err)
    view_state.phase = "blocked"
    view_state.error = tostring(queue_err)
    update(bufnr, view_state)
  end)
end

function M.apply(bufnr, open_after)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "revert" then
    return nil, errors.new("revert_buffer_missing", "could not locate the CVS revert plan")
  end
  local view_state = attachment.view_state
  if view_state.phase ~= "ready" then
    util.notify("The CVS revert plan is not ready to apply.", vim.log.levels.WARN)
    return nil
  end

  local prompt = ("Apply the reverse of CVS commit %s to %d file%s?"):format(
    view_state.commit_id, #view_state.items, #view_state.items == 1 and "" or "s"
  )
  local confirmed
  if M._confirm then
    confirmed = M._confirm(prompt, view_state)
  else
    confirmed = vim.fn.confirm(prompt, "&Apply\n&Cancel", 2) == 1
  end
  if not confirmed then
    return nil
  end

  -- The plan may have remained open while files changed. Repeat the targeted
  -- preflight immediately before the first mutating CVS command.
  check_working_copy(bufnr, view_state, function()
    apply_ready(bufnr, view_state, open_after)
  end)
  return true
end

function M.commit(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "revert" then
    return nil
  end
  if attachment.view_state.phase == "ready" then
    return M.apply(bufnr, true)
  elseif attachment.view_state.phase == "applied" then
    return open_commit(attachment.view_state)
  end
  util.notify("The CVS revert is not ready to commit.", vim.log.levels.WARN)
  return nil
end

function M.copy_commit_id(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "revert" then
    return nil
  end
  local id = attachment.view_state.commit_id
  vim.fn.setreg('"', id)
  util.notify(("Copied CVS commit ID %s."):format(id))
  return id
end

return M
