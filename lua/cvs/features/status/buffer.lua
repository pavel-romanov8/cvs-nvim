local actions = require("cvs.features.status.actions")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}
local namespace = vim.api.nvim_create_namespace("cvs-status")

local function render(bufnr, view_state)
  local lines, row_map, highlights = require("cvs.features.status.render").lines(view_state)
  view_state.row_map = row_map
  ui_buffer.set_lines(bufnr, lines)

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      bufnr,
      namespace,
      item.group,
      item.row - 1,
      item.start_col,
      item.end_col
    )
  end
end

local function close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function first_item_row(row_map)
  local first = nil
  for row, target in pairs(row_map or {}) do
    if target.kind == "file" and (not first or row < first) then
      first = row
    end
  end

  return first or 1
end

function M.get_current_item(bufnr)
  local attachment = state.get_buffer(bufnr)
  local view_state = attachment and attachment.view_state
  if not view_state or not view_state.row_map then
    return nil
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local target = view_state.row_map[row]
  return target and target.kind == "file" and target.item or nil
end

local function collect_targets(bufnr, start_row, end_row, predicate)
  local attachment = state.get_buffer(bufnr)
  local view_state = attachment and attachment.view_state
  if not view_state or not view_state.row_map then
    return {}
  end

  start_row = start_row or vim.api.nvim_win_get_cursor(0)[1]
  end_row = end_row or start_row
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  local targets = {}
  local seen = {}
  local skipped = 0
  local include_sections = start_row == end_row
  local function append(item)
    if not item or seen[item.path] then
      return
    end

    seen[item.path] = true
    if predicate(item) then
      targets[#targets + 1] = item
    else
      skipped = skipped + 1
    end
  end

  for row = start_row, end_row do
    local target = view_state.row_map[row]
    if target and target.kind == "file" then
      append(target.item)
    elseif include_sections and target and target.kind == "section" then
      for _, item in ipairs(target.section.items or {}) do
        append(item)
      end
    end
  end

  return targets, skipped
end

function M.get_targets(bufnr, start_row, end_row)
  return collect_targets(bufnr, start_row, end_row, function(item)
    return item.selectable
  end)
end

function M.get_add_targets(bufnr, start_row, end_row)
  return collect_targets(bufnr, start_row, end_row, function(item)
    return item.status == "unknown" or item.status == "removed"
  end)
end

function M.get_binary_add_targets(bufnr, start_row, end_row)
  return collect_targets(bufnr, start_row, end_row, function(item)
    return item.status == "unknown"
  end)
end

function M.get_remove_targets(bufnr, start_row, end_row)
  return collect_targets(bufnr, start_row, end_row, function(item)
    return item.status ~= "unknown"
      and item.status ~= "removed"
      and item.status ~= "updated"
      and item.status ~= "patched"
  end)
end

function M.open(view_state, opts)
  opts = opts or {}
  local origin_win = vim.api.nvim_get_current_win()

  local bufnr = ui_buffer.create({
    name = ("cvs://status/%s"):format(view_state.workspace.root_dir),
    filetype = "cvs-status",
  })

  render(bufnr, view_state)
  ui_buffer.lock(bufnr)
  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        close_buffer(bufnr)
      end,
      desc = "Close CVS status",
    },
    {
      mode = "n",
      lhs = "R",
      rhs = function()
        actions.refresh(bufnr)
      end,
      desc = "Refresh CVS status",
    },
    {
      mode = "n",
      lhs = "<CR>",
      rhs = function()
        actions.open_current(bufnr)
      end,
      desc = "Open current file",
    },
    {
      mode = "n",
      lhs = "o",
      rhs = function()
        actions.open_current(bufnr, "split")
      end,
      desc = "Open current file in a split",
    },
    {
      mode = "n",
      lhs = "gO",
      rhs = function()
        actions.open_current(bufnr, "vsplit")
      end,
      desc = "Open current file in a vertical split",
    },
    {
      mode = "n",
      lhs = "O",
      rhs = function()
        actions.open_current(bufnr, "tab")
      end,
      desc = "Open current file in a tab",
    },
    {
      mode = "n",
      lhs = "p",
      rhs = function()
        actions.open_current(bufnr, "preview")
      end,
      desc = "Open current file in preview",
    },
    {
      mode = "n",
      lhs = "dd",
      rhs = function()
        actions.diff_current(bufnr)
      end,
      desc = "Diff current file against its CVS base",
    },
    {
      mode = "n",
      lhs = "=",
      rhs = function()
        actions.toggle_inline_diff(bufnr)
      end,
      desc = "Toggle inline CVS diff",
    },
    {
      mode = "n",
      lhs = "-",
      rhs = function()
        actions.toggle_selection(bufnr)
      end,
      desc = "Toggle CVS commit selection",
    },
    {
      mode = "x",
      lhs = "-",
      rhs = function()
        actions.toggle_selection(bufnr, vim.fn.line("v"), vim.fn.line("."))
      end,
      desc = "Toggle CVS commit selection",
    },
    {
      mode = "n",
      lhs = "cc",
      rhs = function()
        actions.commit_selected(bufnr)
      end,
      desc = "Commit selected CVS files",
    },
    {
      mode = "n",
      lhs = "a",
      rhs = function()
        actions.add_current(bufnr)
      end,
      desc = "Add current file to CVS",
    },
    {
      mode = "x",
      lhs = "a",
      rhs = function()
        actions.add_current(bufnr, vim.fn.line("v"), vim.fn.line("."))
      end,
      desc = "Add selected files to CVS",
    },
    {
      mode = "n",
      lhs = "A",
      rhs = function()
        actions.add_binary(bufnr)
      end,
      desc = "Add current file to CVS as binary",
    },
    {
      mode = "x",
      lhs = "A",
      rhs = function()
        actions.add_binary(bufnr, vim.fn.line("v"), vim.fn.line("."))
      end,
      desc = "Add selected files to CVS as binary",
    },
    {
      mode = "n",
      lhs = "r",
      rhs = function()
        actions.remove_current(bufnr)
      end,
      desc = "Remove current file from CVS",
    },
  })

  state.attach_buffer(bufnr, {
    kind = "status",
    root_dir = view_state.workspace.root_dir,
    origin_win = origin_win,
    view_state = view_state,
  })

  local status_config = require("cvs.config").get().ui.status
  local winid = window.open(bufnr, {
    kind = opts.kind or status_config.kind,
    height = opts.height or status_config.height,
  })

  vim.api.nvim_win_set_cursor(winid, { first_item_row(view_state.row_map), 0 })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      require("cvs.features.status.service").cancel_inline_diff(bufnr)
      state.detach_buffer(bufnr)
    end,
  })

  return bufnr, winid
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local winids = vim.fn.win_findbuf(bufnr)
  local cursor = nil
  local cursor_path = nil
  local cursor_path_offset = 0
  local was_loading = false
  if winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
    cursor = vim.api.nvim_win_get_cursor(winids[1])
    local current = state.get_buffer(bufnr)
    local current_view = current and current.view_state
    local current_row_map = current_view and current_view.row_map
    local target = current_row_map and current_row_map[cursor[1]]
    was_loading = current_view and current_view.loading == true
    if target and target.kind == "file" then
      cursor_path = target.item.path
      local first = cursor[1]
      for row, candidate in pairs(current_row_map) do
        if candidate.kind == "file" and candidate.item.path == cursor_path and row < first then
          first = row
        end
      end
      cursor_path_offset = cursor[1] - first
    end
  end

  local attachment = state.get_buffer(bufnr) or {}
  attachment.kind = "status"
  attachment.root_dir = view_state.workspace.root_dir
  attachment.view_state = view_state
  state.attach_buffer(bufnr, attachment)

  render(bufnr, view_state)
  ui_buffer.lock(bufnr)

  if cursor and winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
    local max_line = vim.api.nvim_buf_line_count(bufnr)
    local row = nil
    if cursor_path then
      for candidate, target in pairs(view_state.row_map or {}) do
        if target.kind == "file" and target.item.path == cursor_path and (not row or candidate < row) then
          row = candidate
        end
      end
      local offset_row = row and row + cursor_path_offset or nil
      local offset_target = offset_row and view_state.row_map[offset_row]
      if offset_target and offset_target.kind == "file" and offset_target.item.path == cursor_path then
        row = offset_row
      end
    elseif was_loading then
      row = first_item_row(view_state.row_map)
    end
    vim.api.nvim_win_set_cursor(winids[1], {
      row or math.max(1, math.min(cursor[1], max_line)),
      cursor[2],
    })
  end
end

return M
