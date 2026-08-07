local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local parse = require("cvs.features.status.parse")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local types = require("cvs.core.types")
local util = require("cvs.core.util")
local uv = vim.uv or vim.loop

local M = {}
local initialized = false

local status_order = {
  [types.status.modified] = 1,
  [types.status.added] = 2,
  [types.status.removed] = 3,
  [types.status.unknown] = 4,
  [types.status.conflict] = 5,
  [types.status.updated] = 6,
  [types.status.patched] = 7,
}

local section_titles = {
  [types.status.modified] = "Modified",
  [types.status.added] = "Added",
  [types.status.removed] = "Removed",
  [types.status.unknown] = "Unknown",
  [types.status.conflict] = "Conflicts",
  [types.status.updated] = "Updated",
  [types.status.patched] = "Patched",
}

local committable_statuses = {
  [types.status.modified] = true,
  [types.status.added] = true,
  [types.status.removed] = true,
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

local function sort_items(items)
  table.sort(items, function(left, right)
    return left.path < right.path
  end)
end

local function build_sections(snapshot, selected)
  local grouped = {}
  local counts = {}
  local total_count = 0
  local selected_state = {}
  local selectable_count = 0
  local selected_count = 0

  selected = selected or {}

  for _, file in ipairs(snapshot.files or {}) do
    -- U reports an incoming repository change, not a working-copy change.
    if file.status ~= types.status.updated then
      total_count = total_count + 1
      counts[file.status] = (counts[file.status] or 0) + 1

      if not grouped[file.status] then
        grouped[file.status] = {
          kind = file.status,
          title = section_titles[file.status] or file.status,
          items = {},
          selectable_count = 0,
          selected_count = 0,
        }
      end

      local selectable = committable_statuses[file.status] == true
      local is_selected = selectable and selected[file.path] == true
      grouped[file.status].items[#grouped[file.status].items + 1] = {
        code = file.code,
        path = file.path,
        status = file.status,
        selectable = selectable,
        selected = is_selected,
      }

      if selectable then
        selectable_count = selectable_count + 1
        grouped[file.status].selectable_count = grouped[file.status].selectable_count + 1
        if is_selected then
          selected_state[file.path] = true
          selected_count = selected_count + 1
          grouped[file.status].selected_count = grouped[file.status].selected_count + 1
        end
      end
    end
  end

  local sections = {}
  for _, section in pairs(grouped) do
    sort_items(section.items)
    sections[#sections + 1] = section
  end

  table.sort(sections, function(left, right)
    local left_index = status_order[left.kind] or 99
    local right_index = status_order[right.kind] or 99
    if left_index ~= right_index then
      return left_index < right_index
    end

    return (left.title or "") < (right.title or "")
  end)

  return sections, counts, total_count, selected_state, selectable_count, selected_count
end

local function build_view_state(snapshot, opts, previous)
  previous = previous or {}
  local sections, counts, total_count, selected, selectable_count, selected_count =
    build_sections(snapshot, previous.selected)
  local stored_opts = vim.tbl_extend("force", {}, opts or {})
  stored_opts.force = nil

  return {
    workspace = snapshot.workspace,
    scope_label = scope_label(snapshot.workspace, opts or {}),
    opts = stored_opts,
    status_snapshot = snapshot,
    generated_at = snapshot.generated_at,
    cached = snapshot.cached == true,
    sections = sections,
    counts = counts,
    total_count = total_count,
    selected = selected,
    selectable_count = selectable_count,
    selected_count = selected_count,
    messages = vim.deepcopy(previous.messages or snapshot.messages or {}),
    loading = snapshot.loading == true,
    refreshing = previous.refreshing == true,
  }
end

local function update_selection(view_state)
  local selected = view_state.selected or {}
  local selected_state = {}
  local selectable_count = 0
  local selected_count = 0

  for _, section in ipairs(view_state.sections or {}) do
    section.selectable_count = 0
    section.selected_count = 0

    for _, item in ipairs(section.items or {}) do
      item.selectable = committable_statuses[item.status] == true
      item.selected = item.selectable and selected[item.path] == true

      if item.selectable then
        selectable_count = selectable_count + 1
        section.selectable_count = section.selectable_count + 1
        if item.selected then
          selected_state[item.path] = true
          selected_count = selected_count + 1
          section.selected_count = section.selected_count + 1
        end
      end
    end
  end

  view_state.selected = selected_state
  view_state.selectable_count = selectable_count
  view_state.selected_count = selected_count
end

local function cache_key(opts)
  local files = opts.files or {}
  if not opts.path and #files == 0 then
    return "workspace"
  end

  local parts = {}
  local function append(kind, value)
    value = tostring(value)
    parts[#parts + 1] = ("%s:%d:%s"):format(kind, #value, value)
  end

  if opts.path then
    append("path", opts.path)
  end
  for _, file in ipairs(files) do
    append("file", file)
  end

  return table.concat(parts, "|")
end

local function cached_snapshot(workspace, opts)
  local cache_config = require("cvs.config").get().status.cache
  if opts.force or cache_config.enabled == false then
    return nil
  end

  local entry = state.get_status_cache(workspace.root_dir, cache_key(opts))
  if not entry then
    return nil
  end

  local age_ms = (uv.hrtime() - entry.cached_at) / 1000000
  if cache_config.ttl_ms and age_ms >= cache_config.ttl_ms then
    return nil
  end

  return vim.tbl_extend("force", {}, entry.snapshot, {
    workspace = workspace,
    cached = true,
  })
end

local function store_cached_snapshot(snapshot, opts)
  if not snapshot.result or snapshot.result.code ~= 0 then
    return
  end

  local cache_config = require("cvs.config").get().status.cache
  if cache_config.enabled == false then
    return
  end

  state.set_status_cache(snapshot.workspace.root_dir, cache_key(opts), {
    snapshot = snapshot,
    cached_at = uv.hrtime(),
  })
end

local function finish_collection(snapshot, opts)
  state.set_snapshot(snapshot.workspace.root_dir, snapshot)
  store_cached_snapshot(snapshot, opts)
  events.emit("CvsStatusRefreshed", {
    root_dir = snapshot.workspace.root_dir,
    cached = snapshot.cached == true,
  })
  return snapshot
end

function M.setup()
  if initialized then
    return
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("CvsStatusCache", { clear = true }),
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path == "" then
        return
      end

      local workspace = context.detect(uv.fs_realpath(path) or path)
      if workspace then
        state.invalidate_status_cache(workspace.root_dir)
      end
    end,
  })

  initialized = true
end

local function get_attachment(bufnr)
  local attachment = state.get_buffer(bufnr)
  if attachment and attachment.kind == "status" then
    return attachment, attachment.view_state
  end

  return nil, nil
end

local function resolve_target_path(workspace, path)
  if vim.startswith(path, workspace.root_dir .. "/") then
    return path
  end

  return util.path_join(workspace.root_dir, path)
end

local function usable_target_window(winid, status_bufnr)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  if vim.api.nvim_win_get_tabpage(winid) ~= vim.api.nvim_get_current_tabpage() then
    return false
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  if bufnr == status_bufnr or vim.bo[bufnr].buftype ~= "" then
    return false
  end

  if vim.fn.exists("+winfixbuf") == 1 and vim.wo[winid].winfixbuf then
    return false
  end

  return vim.api.nvim_win_get_config(winid).relative == ""
end

local function target_window(attachment, status_bufnr)
  if usable_target_window(attachment.origin_win, status_bufnr) then
    return attachment.origin_win
  end

  local alternate = vim.fn.win_getid(vim.fn.winnr("#"))
  if usable_target_window(alternate, status_bufnr) then
    return alternate
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable_target_window(winid, status_bufnr) then
      return winid
    end
  end

  vim.cmd("aboveleft new")
  return vim.api.nvim_get_current_win()
end

local function update_view(bufnr, next_state)
  require("cvs.features.status.buffer").update(bufnr, next_state)
  return next_state
end

function M.collect(opts)
  opts = opts or {}

  local workspace = opts.workspace
  local err
  if not workspace then
    workspace, err = context.detect(opts.path)
  end
  if not workspace then
    return nil, err
  end

  local cache_config = require("cvs.config").get().status.cache
  if opts.force then
    state.invalidate_status_cache(workspace.root_dir)
  elseif cache_config.enabled == false then
    state.clear_status_cache(workspace.root_dir)
  end

  local cached = cached_snapshot(workspace, opts)
  if cached then
    state.set_snapshot(workspace.root_dir, cached)
    events.emit("CvsStatusRefreshed", {
      root_dir = workspace.root_dir,
      cached = true,
    })
    return cached
  end

  local snapshot = {
    workspace = workspace,
    files = {},
    messages = {},
    generated_at = os.date("%Y-%m-%d %H:%M:%S"),
    cached = false,
  }

  local caps = capabilities.detect()
  if not caps.executable then
    snapshot.messages[#snapshot.messages + 1] = ("CVS executable is not available: %s"):format(caps.bin)
  else
    snapshot.result = runner.run(cmd.status(opts), {
      cwd = workspace.root_dir,
    })

    local parsed = parse.parse(snapshot.result.stdout)
    snapshot.files = parsed.files
    snapshot.messages = vim.list_extend(parsed.messages, snapshot.result.stderr)
  end

  return finish_collection(snapshot, opts)
end

function M.collect_async(opts, callback)
  opts = opts or {}
  callback = callback or function() end

  local workspace = opts.workspace
  local err
  if not workspace then
    workspace, err = context.detect(opts.path)
  end
  if not workspace then
    callback(nil, err)
    return nil
  end
  local cache_config = require("cvs.config").get().status.cache
  if opts.force then
    state.invalidate_status_cache(workspace.root_dir)
  elseif cache_config.enabled == false then
    state.clear_status_cache(workspace.root_dir)
  end
  local cache_generation = state.get_status_cache_generation(workspace.root_dir)

  local cached = cached_snapshot(workspace, opts)
  if cached then
    state.set_snapshot(workspace.root_dir, cached)
    events.emit("CvsStatusRefreshed", {
      root_dir = workspace.root_dir,
      cached = true,
    })
    callback(cached)
    return nil
  end

  local snapshot = {
    workspace = workspace,
    files = {},
    messages = {},
    generated_at = os.date("%Y-%m-%d %H:%M:%S"),
    cached = false,
  }

  local caps = capabilities.detect()
  if not caps.executable then
    snapshot.messages[#snapshot.messages + 1] = ("CVS executable is not available: %s"):format(caps.bin)
    callback(finish_collection(snapshot, opts))
    return nil
  end

  return runner.run(cmd.status(opts), {
    cwd = workspace.root_dir,
  }, function(result)
    if state.get_status_cache_generation(workspace.root_dir) ~= cache_generation then
      local retry_opts = vim.tbl_extend("force", {}, opts, {
        force = false,
      })
      M.collect_async(retry_opts, callback)
      return
    end

    snapshot.result = result
    local parsed = parse.parse(result.stdout)
    snapshot.files = parsed.files
    snapshot.messages = vim.list_extend(parsed.messages, result.stderr)
    callback(finish_collection(snapshot, opts))
  end)
end

function M.open(opts)
  opts = opts or {}

  if not opts.path then
    local bufnr = vim.api.nvim_get_current_buf()
    local attachment = get_attachment(bufnr)
    if attachment then
      if opts.force then
        M.refresh(bufnr)
      end

      return bufnr, vim.api.nvim_get_current_win()
    end
  end

  local workspace, err = context.detect(opts.path)
  if not workspace then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local loading_snapshot = {
    workspace = workspace,
    files = {},
    messages = {},
    generated_at = "-",
    loading = true,
  }
  local bufnr, winid = require("cvs.features.status.buffer").open(build_view_state(loading_snapshot, opts), opts)
  local attachment = state.get_buffer(bufnr)
  attachment.status_request_id = (attachment.status_request_id or 0) + 1
  local request_id = attachment.status_request_id
  state.attach_buffer(bufnr, attachment)
  local collect_opts = vim.tbl_extend("force", {}, opts, {
    workspace = workspace,
  })

  M.collect_async(collect_opts, function(snapshot, collect_err)
    local current_attachment = state.get_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr)
      or not current_attachment
      or current_attachment.status_request_id ~= request_id
    then
      return
    end
    if not snapshot then
      util.notify(errors.to_string(collect_err), vim.log.levels.ERROR)
      return
    end

    update_view(bufnr, build_view_state(snapshot, opts))
  end)

  return bufnr, winid
end

function M.refresh(bufnr, extra, callback)
  extra = extra or {}

  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  attachment.status_request_id = (attachment.status_request_id or 0) + 1
  local request_id = attachment.status_request_id
  state.attach_buffer(bufnr, attachment)

  view_state.refreshing = true
  update_view(bufnr, view_state)

  local collect_opts = vim.tbl_extend("force", {}, view_state.opts, {
    force = extra.force ~= false,
    workspace = view_state.workspace,
  })
  local selected = vim.deepcopy(view_state.selected or {})

  return M.collect_async(collect_opts, function(snapshot, err)
    local current_attachment, current_state = get_attachment(bufnr)
    if not current_attachment then
      if callback then
        callback(nil, errors.new("status_buffer_missing", "the CVS status buffer was closed during refresh"))
      end
      return
    end
    if current_attachment.status_request_id ~= request_id then
      if callback then
        callback(nil, errors.new("status_refresh_superseded", "the CVS status refresh was superseded"))
      end
      return
    end

    if not snapshot then
      current_state.refreshing = false
      update_view(bufnr, current_state)
      util.notify(errors.to_string(err), vim.log.levels.ERROR)
      if callback then
        callback(nil, err)
      end
      return
    end

    local next_state = build_view_state(snapshot, view_state.opts, {
      messages = extra.messages,
      selected = selected,
    })
    next_state.refreshing = false
    update_view(bufnr, next_state)
    if callback then
      callback(next_state)
    end
  end)
end

function M.toggle_selection(bufnr, start_row, end_row)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local targets = require("cvs.features.status.buffer").get_targets(bufnr, start_row, end_row)
  if #targets == 0 then
    util.notify("Only modified, added, or removed files can be selected for commit.", vim.log.levels.WARN)
    return nil
  end

  view_state.selected = view_state.selected or {}
  local select_targets = false
  for _, item in ipairs(targets) do
    if not view_state.selected[item.path] then
      select_targets = true
      break
    end
  end

  for _, item in ipairs(targets) do
    view_state.selected[item.path] = select_targets or nil
  end

  update_selection(view_state)
  update_view(bufnr, view_state)
  return select_targets
end

function M.commit_selected(bufnr)
  local attachment, current_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  if (current_state.selected_count or 0) == 0 then
    local err = errors.new("commit_files_empty", "select at least one file before committing")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return M.refresh(bufnr, nil, function(view_state, refresh_err)
    if not view_state then
      if refresh_err and refresh_err.kind == "status_refresh_superseded" then
        util.notify("Commit canceled because a newer status refresh started; press cc again.", vim.log.levels.WARN)
      end
      return
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
      return
    end

    local source_win
    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
      if vim.api.nvim_win_is_valid(winid) then
        source_win = winid
        break
      end
    end

    require("cvs.features.commit.service").open({
      workspace = view_state.workspace,
      files = files,
      source_bufnr = bufnr,
      source_win = source_win,
    })
  end)
end

function M.open_current(bufnr, kind)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "status" then
    return nil
  end

  local item = require("cvs.features.status.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  local target = resolve_target_path(attachment.view_state.workspace, item.path)
  if vim.fn.filereadable(target) == 0 and vim.fn.isdirectory(target) == 0 then
    util.notify(("%s is not available in the working copy."):format(item.path), vim.log.levels.WARN)
    return nil
  end

  local escaped = vim.fn.fnameescape(target)
  if kind == "split" then
    vim.cmd("aboveleft split " .. escaped)
  elseif kind == "vsplit" then
    vim.cmd("leftabove vsplit " .. escaped)
  elseif kind == "tab" then
    vim.cmd("tabedit " .. escaped)
  elseif kind == "preview" then
    vim.cmd("pedit " .. escaped)
  else
    vim.api.nvim_set_current_win(target_window(attachment, bufnr))
    vim.cmd("edit " .. escaped)
  end
  return target
end

function M.diff_current(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "status" then
    return nil
  end

  local item = require("cvs.features.status.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  local target = resolve_target_path(attachment.view_state.workspace, item.path)
  return require("cvs.features.diff.service").open({
    path = target,
  })
end

function M.toggle_inline_diff(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local item = require("cvs.features.status.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  if view_state.inline_diff and view_state.inline_diff.path == item.path then
    view_state.inline_diff = nil
    update_view(bufnr, view_state)
    return true
  end

  if item.status ~= types.status.modified then
    util.notify("Inline diff is currently available for modified files only.", vim.log.levels.WARN)
    return nil
  end

  local target = resolve_target_path(view_state.workspace, item.path)
  if vim.fn.filereadable(target) ~= 1 then
    util.notify(("Could not read %s for inline diff."):format(item.path), vim.log.levels.WARN)
    return nil
  end

  view_state.inline_diff = {
    path = item.path,
    lines = { "Loading diff..." },
    loading = true,
  }
  update_view(bufnr, view_state)

  return runner.run(cmd.diff({ path = item.path }), {
    cwd = view_state.workspace.root_dir,
  }, function(result)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local current_attachment, current_state = get_attachment(bufnr)
    local inline_diff = current_state and current_state.inline_diff
    if not current_attachment or not inline_diff or inline_diff.path ~= item.path or not inline_diff.loading then
      return
    end

    if result.code > 1 then
      current_state.inline_diff = nil
      update_view(bufnr, current_state)
      local message = result.stderr[1] or result.stdout[1] or ("CVS diff exited with code %d."):format(result.code)
      util.notify(message, vim.log.levels.ERROR)
      return
    end

    if #result.stdout == 0 then
      current_state.inline_diff = nil
      update_view(bufnr, current_state)
      return
    end

    current_state.inline_diff = {
      path = item.path,
      lines = result.stdout,
    }
    update_view(bufnr, current_state)
  end)
end

local function add_targets(bufnr, start_row, end_row, binary)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local status_buffer = require("cvs.features.status.buffer")
  local targets, skipped
  if binary then
    targets, skipped = status_buffer.get_binary_add_targets(bufnr, start_row, end_row)
  else
    targets, skipped = status_buffer.get_add_targets(bufnr, start_row, end_row)
  end

  if #targets == 0 then
    local message = "Only unknown or removed files can be added from this view."
    if binary then
      message = "Only unknown files can be added as binary from this view."
    end
    util.notify(message, vim.log.levels.WARN)
    return nil
  end

  if skipped > 0 then
    local suffix = skipped == 1 and "" or "s"
    local mode = binary and " as binary" or ""
    util.notify(("Skipped %d file%s that cannot be added%s."):format(skipped, suffix, mode), vim.log.levels.WARN)
  end

  local files = {}
  for _, item in ipairs(targets) do
    files[#files + 1] = item.path
  end

  return require("cvs.features.files.service").add({
    workspace = view_state.workspace,
    files = files,
    binary = binary,
    on_complete = function(result)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local current_attachment, current_state = get_attachment(bufnr)
      if not current_attachment then
        return
      end

      current_state.selected = current_state.selected or {}
      for _, item in ipairs(targets) do
        if result.code == 0 or item.status == types.status.unknown then
          current_state.selected[item.path] = true
        end
      end

      local message
      if result.code == 0 and #targets == 1 then
        if binary then
          message = ("Added %s to CVS as binary."):format(targets[1].path)
        elseif targets[1].status == types.status.removed then
          message = ("Restored %s in CVS."):format(targets[1].path)
        else
          message = ("Added %s to CVS."):format(targets[1].path)
        end
      elseif result.code == 0 and binary then
        message = ("Added %d binary files to CVS."):format(#targets)
      elseif result.code == 0 then
        message = ("Added or restored %d files in CVS."):format(#targets)
      else
        message = result.stderr[1] or result.stdout[1] or ("CVS add exited with code %d."):format(result.code)
      end

      M.refresh(bufnr, {
        messages = { message },
        force = false,
      })
    end,
  })
end

function M.add_current(bufnr, start_row, end_row)
  return add_targets(bufnr, start_row, end_row, false)
end

function M.add_binary(bufnr, start_row, end_row)
  return add_targets(bufnr, start_row, end_row, true)
end

function M.remove_current(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local item = require("cvs.features.status.buffer").get_current_item(bufnr)
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
        messages = { message },
        force = false,
      })
    end,
  })
end

M._build_view_state = build_view_state
M._cache_key = cache_key

return M
