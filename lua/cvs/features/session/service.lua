local cmd = require("cvs.cvs.cmd")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local types = require("cvs.core.types")
local util = require("cvs.core.util")

local M = {}

local status_order = {
  [types.status.modified] = 1,
  [types.status.added] = 2,
  [types.status.removed] = 3,
  [types.status.unknown] = 4,
  [types.status.conflict] = 5,
  [types.status.updated] = 6,
  [types.status.patched] = 7,
}

local function scope_label(workspace, opts)
  if opts.path then
    local prefix = workspace.root_dir .. "/"
    if opts.path:sub(1, #prefix) == prefix then
      return opts.path:sub(#prefix + 1)
    end

    return opts.path
  end

  return "workspace"
end

local function selected_copy(selected)
  return vim.deepcopy(selected or {})
end

local function merge_selected(base, overrides)
  local merged = selected_copy(base)
  for path, value in pairs(overrides or {}) do
    merged[path] = value
  end
  return merged
end

local function refresh_status(opts)
  local ok, result = pcall(require("cvs.features.status.service").collect, opts)
  if ok then
    return result
  end

  return nil
end

local function classify_file(file, selected)
  local item = {
    code = file.code,
    path = file.path,
    status = file.status,
    selected = false,
    selectable = false,
    section = nil,
  }

  if file.status == types.status.modified or file.status == types.status.added or file.status == types.status.removed then
    item.section = "outgoing"
    item.selectable = true
    if selected[file.path] == nil then
      item.selected = true
    else
      item.selected = selected[file.path] == true
    end
  elseif file.status == types.status.unknown or file.status == types.status.conflict then
    item.section = "attention"
  elseif file.status == types.status.updated or file.status == types.status.patched then
    item.section = "incoming"
  end

  return item.section and item or nil
end

local function sort_items(items)
  table.sort(items, function(left, right)
    local left_index = status_order[left.status] or 99
    local right_index = status_order[right.status] or 99
    if left_index ~= right_index then
      return left_index < right_index
    end

    return left.path < right.path
  end)
end

local function build_sections(snapshot, selected)
  local sections = {
    outgoing = {
      kind = "outgoing",
      title = "Selected Changes",
      items = {},
    },
    attention = {
      kind = "attention",
      title = "Needs Action",
      items = {},
    },
    incoming = {
      kind = "incoming",
      title = "Incoming Changes",
      items = {},
    },
  }

  local selected_state = {}
  local selectable_count = 0
  local selected_count = 0

  for _, file in ipairs(snapshot.files or {}) do
    local item = classify_file(file, selected)
    if item then
      sections[item.section].items[#sections[item.section].items + 1] = item
      if item.selectable then
        selectable_count = selectable_count + 1
        selected_state[item.path] = item.selected
        if item.selected then
          selected_count = selected_count + 1
        end
      end
    end
  end

  local result = {}
  for _, section in pairs(sections) do
    sort_items(section.items)
    result[#result + 1] = section
  end

  table.sort(result, function(left, right)
    return (left.kind or "") < (right.kind or "")
  end)

  return result, selected_state, selectable_count, selected_count
end

local function build_view_state(snapshot, opts, previous)
  previous = previous or {}
  local selected = selected_copy(previous.selected)
  local sections, selected_state, selectable_count, selected_count = build_sections(snapshot, selected)

  return {
    phase = previous.phase or "editing",
    workspace = snapshot.workspace,
    scope_label = scope_label(snapshot.workspace, opts),
    opts = vim.tbl_extend("force", {}, opts),
    status_snapshot = snapshot,
    generated_at = snapshot.generated_at,
    message_lines = vim.deepcopy(previous.message_lines or { "" }),
    messages = vim.deepcopy(previous.messages or {}),
    selected = selected_state,
    sections = sections,
    selectable_count = selectable_count,
    selected_count = selected_count,
    command = previous.command,
    result = previous.result,
    started_at = previous.started_at,
    completed_at = previous.completed_at,
  }
end

local function resolve_target_path(workspace, path)
  if vim.startswith(path, workspace.root_dir .. "/") then
    return path
  end

  return util.path_join(workspace.root_dir, path)
end

local function get_attachment(bufnr)
  local attachment = state.get_buffer(bufnr)
  if attachment and attachment.kind == "session" then
    return attachment, attachment.view_state
  end

  return nil, nil
end

local function update_view(bufnr, next_state)
  require("cvs.features.session.buffer").update(bufnr, next_state)
  return next_state
end

function M.open(opts)
  opts = opts or {}

  local snapshot, err = require("cvs.features.status.service").collect(opts)
  if not snapshot then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return require("cvs.features.session.buffer").open(build_view_state(snapshot, opts), opts)
end

function M.refresh(bufnr, extra)
  extra = extra or {}

  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("session_buffer_missing", "could not locate the CVS session buffer state")
  end

  local message_lines = extra.message_lines
  if not message_lines then
    message_lines = require("cvs.features.session.buffer").get_message(bufnr)
  end

  local snapshot = refresh_status(view_state.opts)
  if not snapshot then
    local err = errors.new("status_refresh_failed", "could not refresh the CVS session snapshot")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local next_selected = extra.selected or merge_selected(view_state.selected, extra.selection_overrides)
  local next_state = build_view_state(snapshot, view_state.opts, {
    phase = extra.phase or "editing",
    message_lines = message_lines,
    messages = extra.messages or view_state.messages,
    selected = next_selected,
    command = extra.command or view_state.command,
    result = extra.result or view_state.result,
    started_at = extra.started_at or view_state.started_at,
    completed_at = extra.completed_at or view_state.completed_at,
  })

  return update_view(bufnr, next_state)
end

function M.toggle_current(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("session_buffer_missing", "could not locate the CVS session buffer state")
  end

  local item = require("cvs.features.session.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  if not item.selectable then
    util.notify("This file is not directly committable yet.", vim.log.levels.WARN)
    return nil
  end

  local message_lines = require("cvs.features.session.buffer").get_message(bufnr)
  local next_selected = merge_selected(view_state.selected, {
    [item.path] = not item.selected,
  })

  return M.refresh(bufnr, {
    message_lines = message_lines,
    selected = next_selected,
    messages = view_state.messages,
  })
end

function M.open_current(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "session" then
    return nil
  end

  local item = require("cvs.features.session.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  local target = resolve_target_path(attachment.view_state.workspace, item.path)
  if vim.fn.filereadable(target) == 0 and vim.fn.isdirectory(target) == 0 then
    util.notify(("%s is not available in the working copy."):format(item.path), vim.log.levels.WARN)
    return nil
  end

  vim.cmd("edit " .. vim.fn.fnameescape(target))
  return target
end

function M.add_current(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("session_buffer_missing", "could not locate the CVS session buffer state")
  end

  local item = require("cvs.features.session.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  if item.status ~= types.status.unknown and item.status ~= types.status.removed then
    util.notify("Only unknown or removed files can be added from this view.", vim.log.levels.WARN)
    return nil
  end

  local message_lines = require("cvs.features.session.buffer").get_message(bufnr)
  local target = resolve_target_path(view_state.workspace, item.path)

  return require("cvs.features.files.service").add({
    path = target,
    on_complete = function(result)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local message = result.code == 0
        and ((item.status == types.status.removed and "Restored %s in CVS.") or "Added %s to CVS."):format(item.path)
        or (result.stderr[1] or result.stdout[1] or ("CVS add exited with code %d."):format(result.code))

      M.refresh(bufnr, {
        message_lines = message_lines,
        messages = { message },
        selection_overrides = {
          [item.path] = result.code == 0,
        },
      })
    end,
  })
end

function M.remove_current(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("session_buffer_missing", "could not locate the CVS session buffer state")
  end

  local item = require("cvs.features.session.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  if item.status == types.status.unknown then
    util.notify("Use your own file deletion flow for unknown files.", vim.log.levels.WARN)
    return nil
  end

  if item.status == types.status.removed then
    util.notify("This file is already scheduled for removal.", vim.log.levels.INFO)
    return nil
  end

  if item.status == types.status.updated or item.status == types.status.patched then
    util.notify("Update the workspace before removing incoming files.", vim.log.levels.WARN)
    return nil
  end

  local message_lines = require("cvs.features.session.buffer").get_message(bufnr)
  local target = resolve_target_path(view_state.workspace, item.path)

  return require("cvs.features.files.service").remove({
    path = target,
    on_complete = function(result)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local message = result.code == 0
        and ("Scheduled %s for removal."):format(item.path)
        or (result.stderr[1] or result.stdout[1] or ("CVS remove exited with code %d."):format(result.code))

      M.refresh(bufnr, {
        message_lines = message_lines,
        messages = { message },
        selection_overrides = {
          [item.path] = result.code == 0,
        },
      })
    end,
  })
end

function M.submit(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("session_buffer_missing", "could not locate the CVS session buffer state")
  end

  if view_state.phase == "queued" or view_state.phase == "running" then
    return nil, errors.new("commit_in_progress", "a CVS commit is already in progress for this buffer")
  end

  local message_lines, message = require("cvs.features.session.buffer").get_message(bufnr)
  if not message then
    local err = errors.new("commit_message_empty", "commit message cannot be empty")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local files = {}
  for path, selected in pairs(view_state.selected or {}) do
    if selected then
      files[#files + 1] = path
    end
  end
  table.sort(files)

  if #files == 0 then
    local err = errors.new("commit_files_empty", "select at least one file before committing")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local command = cmd.commit(vim.tbl_extend("force", {}, view_state.opts or {}, {
    message = message,
    files = files,
  }))

  view_state.message_lines = message_lines
  view_state.command = command
  view_state.messages = {
    "Commit queued.",
  }
  view_state.phase = queue.is_busy(view_state.workspace.root_dir) and "queued" or "running"
  update_view(bufnr, view_state)

  queue.enqueue(view_state.workspace.root_dir, function(done)
    view_state.phase = "running"
    view_state.started_at = os.date("%Y-%m-%d %H:%M:%S")
    view_state.messages = {
      "Running CVS commit...",
    }
    update_view(bufnr, view_state)

    runner.run(command, {
      cwd = view_state.workspace.root_dir,
    }, function(result)
      local ok, callback_err = pcall(function()
        local messages = vim.deepcopy(result.stdout)
        vim.list_extend(messages, result.stderr)

        local snapshot = refresh_status(view_state.opts) or view_state.status_snapshot
        local next_state = build_view_state(snapshot, view_state.opts, {
          phase = "done",
          message_lines = result.code == 0 and { "" } or message_lines,
          messages = messages,
          selected = result.code == 0 and {} or view_state.selected,
          command = command,
          result = result,
          started_at = view_state.started_at,
          completed_at = os.date("%Y-%m-%d %H:%M:%S"),
        })

        update_view(bufnr, next_state)

        if result.code == 0 then
          events.emit("CvsChanged", {
            root_dir = view_state.workspace.root_dir,
            result = result,
            operation = "commit",
            scope = view_state.scope_label,
            files = files,
          })
          util.notify(("CVS commit completed for %s."):format(view_state.scope_label))
        else
          local message_text = messages[1] or ("CVS commit exited with code %d."):format(result.code)
          util.notify(message_text, vim.log.levels.WARN)
        end
      end)

      if not ok then
        update_view(bufnr, vim.tbl_extend("force", view_state, {
          phase = "done",
          completed_at = os.date("%Y-%m-%d %H:%M:%S"),
          messages = { ("Internal error: %s"):format(callback_err) },
        }))
        util.notify(("CVS commit failed internally: %s"):format(callback_err), vim.log.levels.ERROR)
      end

      done()
    end)
  end, function(queue_err)
    util.notify(("CVS commit queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return command
end

M._build_view_state = build_view_state
M._build_sections = build_sections

return M
