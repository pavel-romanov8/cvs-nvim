local annotate_buffer = require("cvs.features.annotate.buffer")
local config = require("cvs.config")
local state = require("cvs.core.state")

local target_id = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

local function reset_editor()
  state.buffers = {}
  state.workspaces = {}

  config.setup({
    notifications = {
      enabled = false,
    },
    ui = {
      annotate = {
        kind = "left_vsplit",
        author_width = 12,
        auto_refresh_on_save = true,
      },
    },
  })

  vim.o.swapfile = false

  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")

  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_win_set_buf(0, bufnr)

  for _, other in ipairs(vim.api.nvim_list_bufs()) do
    if other ~= bufnr and vim.api.nvim_buf_is_valid(other) then
      pcall(vim.api.nvim_buf_delete, other, { force = true })
    end
  end

  return bufnr
end

local function entries(count)
  local result = {}

  for index = 1, count do
    result[index] = {
      author = ("user%d"):format(index),
      date = ("2024-01-%02d"):format(index),
      revision = ("1.%d"):format(index),
    }
  end

  return result
end

local function view_state(source_bufnr, count)
  target_id = target_id + 1

  return {
    parsed = {
      entries = entries(count),
      messages = {},
    },
    source_bufnr = source_bufnr,
    source_win = vim.api.nvim_get_current_win(),
    target_path = ("test://source-%d"):format(target_id),
    workspace = {
      root_dir = vim.fn.getcwd(),
    },
    stale = false,
    opts = {},
  }
end

local function test_tab_keeps_annotate_visible()
  local source_bufnr = reset_editor()
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "one", "two" })

  local source_tab = vim.api.nvim_get_current_tabpage()
  local _, annotate_win = annotate_buffer.open(view_state(source_bufnr, 2), {
    kind = "tab",
  })

  assert_eq(#vim.api.nvim_list_tabpages(), 2, "annotate opens a new tab")
  assert_eq(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(annotate_win), "annotate tab stays focused")
  assert_true(vim.api.nvim_get_current_tabpage() ~= source_tab, "source tab should not regain focus")
end

local function test_rerenders_when_source_line_count_changes()
  local source_bufnr = reset_editor()
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "one", "two" })

  local source_win = vim.api.nvim_get_current_win()
  local annotate_bufnr = annotate_buffer.open(view_state(source_bufnr, 2), {
    kind = "left_vsplit",
  })

  assert_eq(vim.api.nvim_buf_line_count(annotate_bufnr), 2, "initial annotate line count")

  vim.api.nvim_set_current_win(source_win)
  vim.api.nvim_buf_set_lines(source_bufnr, 2, 2, false, { "three" })
  vim.api.nvim_exec_autocmds("TextChanged", {
    buffer = source_bufnr,
    modeline = false,
  })

  assert_eq(vim.api.nvim_buf_line_count(annotate_bufnr), 3, "annotate grows with the source buffer")
  assert_eq(vim.api.nvim_buf_get_lines(annotate_bufnr, 2, 3, false)[1], "", "new unsaved line renders as blank metadata")
end

local function test_tracks_the_active_source_split()
  local source_bufnr = reset_editor()
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "one", "two", "three", "four" })

  local primary_win = vim.api.nvim_get_current_win()
  local _, annotate_win = annotate_buffer.open(view_state(source_bufnr, 4), {
    kind = "left_vsplit",
  })

  vim.api.nvim_set_current_win(primary_win)
  vim.cmd("split")

  local secondary_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(primary_win, { 1, 0 })
  vim.api.nvim_win_set_cursor(secondary_win, { 4, 0 })
  vim.api.nvim_set_current_win(secondary_win)

  vim.api.nvim_exec_autocmds("CursorMoved", {
    buffer = source_bufnr,
    modeline = false,
  })

  assert_eq(vim.api.nvim_win_get_cursor(annotate_win)[1], 4, "annotate follows the active split cursor")
  assert_eq(state.get_buffer(vim.api.nvim_win_get_buf(annotate_win)).source_win, secondary_win, "state tracks the active source split")
end

return function()
  test_tab_keeps_annotate_visible()
  test_rerenders_when_source_line_count_changes()
  test_tracks_the_active_source_split()
end
