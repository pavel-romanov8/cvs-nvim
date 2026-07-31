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

local function build_sections(snapshot)
  local grouped = {}
  local counts = {}
  local total_count = 0

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
        }
      end

      grouped[file.status].items[#grouped[file.status].items + 1] = {
        code = file.code,
        path = file.path,
        status = file.status,
      }
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

  return sections, counts, total_count
end

local function build_view_state(snapshot, opts, previous)
  previous = previous or {}
  local sections, counts, total_count = build_sections(snapshot)
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
    messages = vim.deepcopy(previous.messages or snapshot.messages or {}),
  }
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

  local workspace, err = context.detect(opts.path)
  if not workspace then
    return nil, err
  end

  local cache_config = require("cvs.config").get().status.cache
  if opts.force or cache_config.enabled == false then
    state.invalidate_status_cache(workspace.root_dir)
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

  state.set_snapshot(workspace.root_dir, snapshot)
  store_cached_snapshot(snapshot, opts)
  events.emit("CvsStatusRefreshed", {
    root_dir = workspace.root_dir,
    cached = false,
  })

  return snapshot
end

function M.open(opts)
  opts = opts or {}

  if not opts.path then
    local bufnr = vim.api.nvim_get_current_buf()
    local attachment = get_attachment(bufnr)
    if attachment then
      if opts.force then
        return M.refresh(bufnr)
      end

      return bufnr, vim.api.nvim_get_current_win()
    end
  end

  local snapshot, err = M.collect(opts)
  if not snapshot then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return require("cvs.features.status.buffer").open(build_view_state(snapshot, opts), opts)
end

function M.refresh(bufnr, extra)
  extra = extra or {}

  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local collect_opts = vim.tbl_extend("force", {}, view_state.opts, {
    force = extra.force ~= false,
  })
  local snapshot, err = M.collect(collect_opts)
  if not snapshot then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return update_view(bufnr, build_view_state(snapshot, view_state.opts, {
    messages = extra.messages,
  }))
end

function M.open_current(bufnr)
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

  vim.api.nvim_set_current_win(target_window(attachment, bufnr))
  vim.cmd("edit " .. vim.fn.fnameescape(target))
  return target
end

function M.add_current(bufnr)
  local attachment, view_state = get_attachment(bufnr)
  if not attachment then
    return nil, errors.new("status_buffer_missing", "could not locate the CVS status buffer state")
  end

  local item = require("cvs.features.status.buffer").get_current_item(bufnr)
  if not item then
    return nil
  end

  if item.status ~= types.status.unknown and item.status ~= types.status.removed then
    util.notify("Only unknown or removed files can be added from this view.", vim.log.levels.WARN)
    return nil
  end

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
        messages = { message },
        force = false,
      })
    end,
  })
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
