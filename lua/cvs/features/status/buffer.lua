local actions = require("cvs.features.status.actions")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

local function render(view_state)
  local lines, row_map = require("cvs.features.status.render").lines(view_state)
  view_state.row_map = row_map
  return lines
end

local function close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function first_item_row(row_map)
  local first = nil
  for row in pairs(row_map or {}) do
    if not first or row < first then
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
  return view_state.row_map[row]
end

function M.open(view_state, opts)
  opts = opts or {}

  local bufnr = ui_buffer.create({
    name = ("cvs://status/%s"):format(view_state.workspace.root_dir),
    filetype = "cvs-status",
  })

  ui_buffer.set_lines(bufnr, render(view_state))
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
      lhs = "a",
      rhs = function()
        actions.add_current(bufnr)
      end,
      desc = "Add current file to CVS",
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
    view_state = view_state,
  })

  local winid = window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.status.kind,
  })

  vim.api.nvim_win_set_cursor(winid, { first_item_row(view_state.row_map), 0 })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
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
  if winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
    cursor = vim.api.nvim_win_get_cursor(winids[1])
  end

  local attachment = state.get_buffer(bufnr) or {}
  attachment.kind = "status"
  attachment.root_dir = view_state.workspace.root_dir
  attachment.view_state = view_state
  state.attach_buffer(bufnr, attachment)

  ui_buffer.set_lines(bufnr, render(view_state))
  ui_buffer.lock(bufnr)

  if cursor and winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
    local max_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(winids[1], {
      math.max(1, math.min(cursor[1], max_line)),
      cursor[2],
    })
  end
end

return M
