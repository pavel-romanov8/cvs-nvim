local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

local function trim_message_lines(lines)
  local first = 1
  local last = #lines

  while first <= #lines and vim.trim(lines[first]) == "" do
    first = first + 1
  end

  while last >= first and vim.trim(lines[last]) == "" do
    last = last - 1
  end

  if first > last then
    return {}
  end

  return vim.list_slice(lines, first, last)
end

local function extract_message_lines(lines)
  local message_lines = {}

  for _, line in ipairs(lines or {}) do
    if not vim.startswith(line, "#") then
      message_lines[#message_lines + 1] = line
    end
  end

  return trim_message_lines(message_lines)
end

local function render(view_state)
  local lines, row_map = require("cvs.features.session.render").lines(view_state)
  view_state.row_map = row_map
  return lines
end

local function close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.get_message(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local message_lines = extract_message_lines(lines)
  if #message_lines == 0 then
    return {}, nil
  end

  return message_lines, table.concat(message_lines, "\n")
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
    name = ("cvs://session/%s"):format(view_state.workspace.root_dir),
    buftype = "acwrite",
    filetype = "cvs-session",
  })

  ui_buffer.set_lines(bufnr, render(view_state))
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      require("cvs.features.session.service").submit(bufnr)
    end,
  })

  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        close_buffer(bufnr)
      end,
      desc = "Close CVS session",
    },
    {
      mode = "n",
      lhs = "<C-c><C-c>",
      rhs = function()
        require("cvs.features.session.service").submit(bufnr)
      end,
      desc = "Submit CVS commit",
    },
    {
      mode = "n",
      lhs = "<space>",
      rhs = function()
        require("cvs.features.session.service").toggle_current(bufnr)
      end,
      desc = "Toggle file selection",
    },
    {
      mode = "n",
      lhs = "a",
      rhs = function()
        require("cvs.features.session.service").add_current(bufnr)
      end,
      desc = "Add current file to CVS",
    },
    {
      mode = "n",
      lhs = "r",
      rhs = function()
        require("cvs.features.session.service").remove_current(bufnr)
      end,
      desc = "Remove current file from CVS",
    },
    {
      mode = "n",
      lhs = "R",
      rhs = function()
        require("cvs.features.session.service").refresh(bufnr)
      end,
      desc = "Refresh CVS session",
    },
    {
      mode = "n",
      lhs = "<CR>",
      rhs = function()
        require("cvs.features.session.service").open_current(bufnr)
      end,
      desc = "Open current file",
    },
  })

  state.attach_buffer(bufnr, {
    kind = "session",
    root_dir = view_state.workspace.root_dir,
    view_state = view_state,
  })

  local winid = window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.session.kind,
  })

  vim.api.nvim_win_set_cursor(winid, { 1, 0 })

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
  attachment.kind = "session"
  attachment.root_dir = view_state.workspace.root_dir
  attachment.view_state = view_state
  state.attach_buffer(bufnr, attachment)

  ui_buffer.set_lines(bufnr, render(view_state))

  if cursor and winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
    local max_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(winids[1], {
      math.max(1, math.min(cursor[1], max_line)),
      cursor[2],
    })
  end
end

M._extract_message_lines = extract_message_lines

return M
