local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")
local mapping = require("cvs.features.annotate.mapping")

local M = {}

local CONTENT_REFRESH_DELAY_MS = 80

local function config_values()
  return require("cvs.config").get().ui.annotate
end

local function source_line_count(view_state)
  if view_state.source_bufnr and vim.api.nvim_buf_is_valid(view_state.source_bufnr) then
    return vim.api.nvim_buf_line_count(view_state.source_bufnr)
  end

  return #(view_state.parsed.entries or {})
end

local function valid_source_win(winid, source_bufnr)
  return winid
    and source_bufnr
    and vim.api.nvim_win_is_valid(winid)
    and vim.api.nvim_win_get_buf(winid) == source_bufnr
end

local function resolve_source_win(source_bufnr, preferred_win, fallback_win)
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return nil
  end

  if valid_source_win(preferred_win, source_bufnr) then
    return preferred_win
  end

  if valid_source_win(fallback_win, source_bufnr) then
    return fallback_win
  end

  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if valid_source_win(winid, source_bufnr) then
      return winid
    end
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if valid_source_win(winid, source_bufnr) then
      return winid
    end
  end

  return nil
end

local function should_restore_focus(source_win, annotate_win)
  return source_win
    and vim.api.nvim_win_is_valid(source_win)
    and annotate_win
    and vim.api.nvim_win_is_valid(annotate_win)
    and vim.api.nvim_win_get_tabpage(source_win) == vim.api.nvim_win_get_tabpage(annotate_win)
end

local function set_content(bufnr, view_state)
  local cfg = config_values()
  local line_count = source_line_count(view_state)
  local entries = view_state.parsed.entries

  if view_state.source_bufnr
    and vim.api.nvim_buf_is_valid(view_state.source_bufnr)
    and (#entries > 0 or view_state.result)
  then
    local source_lines = vim.api.nvim_buf_get_lines(view_state.source_bufnr, 0, -1, false)
    entries, view_state.stale = mapping.entries(entries, source_lines)
  end

  ui_buffer.set_lines(bufnr, require("cvs.features.annotate.render").lines(entries, {
    line_count = line_count,
    author_width = cfg.author_width,
  }))
  ui_buffer.lock(bufnr)

  return line_count
end

local function set_window_options(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local wo = vim.wo[winid]
  wo.number = false
  wo.relativenumber = false
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.winfixwidth = true
  wo.winbar = ""
end

local function sync_view(source_win, annotate_win)
  if not source_win or not annotate_win then
    return
  end

  if not vim.api.nvim_win_is_valid(source_win) or not vim.api.nvim_win_is_valid(annotate_win) then
    return
  end

  local info = vim.fn.getwininfo(source_win)[1]
  if not info then
    return
  end

  local line = vim.api.nvim_win_get_cursor(source_win)[1]
  local max_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(annotate_win))

  line = math.max(1, math.min(line, max_line))

  vim.api.nvim_win_call(annotate_win, function()
    vim.fn.winrestview({
      topline = math.max(1, math.min(info.topline or line, max_line)),
      lnum = line,
      col = 0,
      curswant = 0,
    })
  end)
end

local function close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function setup_autocmds(bufnr, attachment)
  if not attachment.source_bufnr then
    return
  end

  local group = vim.api.nvim_create_augroup(("CvsAnnotate%d"):format(bufnr), { clear = true })

  local function refresh_view()
    local current = state.get_buffer(bufnr)
    if not current then
      return
    end

    current.source_win = resolve_source_win(current.source_bufnr, vim.api.nvim_get_current_win(), current.source_win)
    state.attach_buffer(bufnr, current)
    set_window_options(current.annotate_win)
    sync_view(current.source_win, current.annotate_win)
  end

  local refresh_generation = 0
  local function queue_content_refresh()
    refresh_generation = refresh_generation + 1
    local generation = refresh_generation

    vim.defer_fn(function()
      if generation ~= refresh_generation or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local current = state.get_buffer(bufnr)
      if not current then
        return
      end

      current.line_count = set_content(bufnr, current)
      state.attach_buffer(bufnr, current)
      refresh_view()
    end, CONTENT_REFRESH_DELAY_MS)
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled" }, {
    group = group,
    buffer = attachment.source_bufnr,
    callback = refresh_view,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = attachment.source_bufnr,
    callback = queue_content_refresh,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = attachment.source_bufnr,
    callback = function()
      if config_values().auto_refresh_on_save ~= false then
        require("cvs.features.annotate.service").refresh(attachment.source_bufnr)
      else
        queue_content_refresh()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = attachment.source_bufnr,
    callback = function()
      close_buffer(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      state.detach_buffer(bufnr)
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

local function build_attachment(bufnr, winid, view_state, old)
  old = old or {}
  local source_bufnr = view_state.source_bufnr or old.source_bufnr
  local source_win = resolve_source_win(source_bufnr, view_state.source_win, old.source_win)

  return {
    kind = "annotate",
    source_bufnr = source_bufnr,
    source_win = source_win,
    annotate_win = winid or old.annotate_win,
    target_path = view_state.target_path,
    workspace_root = view_state.workspace.root_dir,
    opts = old.opts or view_state.opts or {},
    stale = view_state.stale,
    command = view_state.command,
    result = view_state.result,
    parsed = view_state.parsed,
    line_count = source_line_count(view_state),
  }
end

function M.open(view_state, opts)
  opts = opts or {}

  local cfg = config_values()
  local bufnr = ui_buffer.create({
    name = ("cvs://annotate/%s"):format(view_state.target_path),
    filetype = "cvs-annotate",
  })

  set_content(bufnr, view_state)
  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        close_buffer(bufnr)
      end,
      desc = "Close CVS annotate",
    },
    {
      mode = "n",
      lhs = "R",
      rhs = function()
        require("cvs.features.annotate.service").refresh(bufnr)
      end,
      desc = "Refresh CVS annotate",
    },
  })

  local winid = window.open(bufnr, {
    kind = opts.kind or cfg.kind,
    width = opts.width or cfg.width,
  })

  local attachment = build_attachment(bufnr, winid, view_state)
  state.attach_buffer(bufnr, attachment)
  set_window_options(winid)
  setup_autocmds(bufnr, attachment)
  sync_view(attachment.source_win, winid)

  if should_restore_focus(attachment.source_win, winid) then
    vim.api.nvim_set_current_win(attachment.source_win)
  end

  return bufnr, winid
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  set_content(bufnr, view_state)

  local old = state.get_buffer(bufnr) or {}
  local attachment = build_attachment(bufnr, old.annotate_win, view_state, old)
  state.attach_buffer(bufnr, attachment)
  set_window_options(attachment.annotate_win)
  sync_view(attachment.source_win, attachment.annotate_win)

  return bufnr, attachment.annotate_win
end

return M
