local config = require("cvs.config")
local state = require("cvs.core.state")
local diff_view = require("cvs.features.diff.view")

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

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  config.setup()
  state.buffers = {}

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_win_set_buf(0, source_bufnr)
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "working change" })
  vim.bo[source_bufnr].filetype = "lua"
  vim.bo[source_bufnr].modified = true
  local source_win = vim.api.nvim_get_current_win()

  local old_bufnr, new_bufnr, old_win, new_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = source_win,
    loading = true,
    opts = {},
  }, {
    kind = "vsplit",
  })

  assert_eq(vim.api.nvim_buf_get_lines(old_bufnr, 0, -1, false)[1], "Loading CVS diff...", "pair opens immediately")
  diff_view.update(old_bufnr, {
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = source_win,
    loading = false,
    parsed = {
      lines = {
        "@@ -1 +1 @@",
        "-base content",
        "+working change",
      },
      hunks = {
        { header = "@@ -1 +1 @@", row = 1 },
      },
    },
    opts = {},
  })

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "streamed diff opens a paired split")
  assert_eq(old_win, source_win, "base hunks replace the source window temporarily")
  assert_eq(vim.api.nvim_win_get_buf(old_win), old_bufnr, "left window displays base hunks")
  assert_eq(vim.api.nvim_win_get_buf(new_win), new_bufnr, "right window displays working hunks")
  assert_eq(vim.wo[old_win].winbar, "CVS BASE", "left side is labeled")
  assert_eq(vim.wo[new_win].winbar, "CVS WORKING", "right side is labeled")

  for _, bufnr in ipairs({ old_bufnr, new_bufnr }) do
    assert_eq(vim.bo[bufnr].filetype, "lua", "hunk buffer keeps source syntax")
    assert_eq(vim.bo[bufnr].readonly, true, "hunk buffer is read-only")
    assert_eq(vim.bo[bufnr].modifiable, false, "hunk buffer is not modifiable")
    assert_eq(vim.bo[bufnr].undolevels, -1, "hunk buffer does not retain undo history")
    assert_eq(state.get_buffer(bufnr).kind, "diff", "paired diff state is attached")
  end

  assert_true(vim.wo[old_win].diff, "base hunk window enables native diff")
  assert_true(vim.wo[new_win].diff, "working hunk window enables native diff")
  assert_true(vim.wo[old_win].scrollbind and vim.wo[new_win].scrollbind, "paired scrolling is synchronized")
  assert_true(vim.wo[old_win].cursorbind and vim.wo[new_win].cursorbind, "paired cursors are synchronized")

  local old_lines = vim.api.nvim_buf_get_lines(old_bufnr, 0, -1, false)
  local new_lines = vim.api.nvim_buf_get_lines(new_bufnr, 0, -1, false)
  assert_eq(old_lines[1], "@@ -1 +1 @@", "both sides retain the hunk anchor")
  assert_eq(old_lines[2], "base content", "left side reconstructs deleted content")
  assert_eq(new_lines[2], "working change", "right side reconstructs added content")
  assert_eq(vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)[1], "working change", "source content is untouched")
  assert_true(vim.bo[source_bufnr].modified, "source remains modified")

  vim.api.nvim_set_current_win(new_win)
  assert_eq(vim.fn.maparg("q", "n", false, true).desc, "Close CVS diff", "both sides can close the view")

  diff_view.close(new_bufnr)
  assert_eq(vim.api.nvim_win_get_buf(source_win), source_bufnr, "closing restores the original source buffer")
  assert_eq(vim.api.nvim_win_is_valid(new_win), false, "closing removes the working hunk window")
  assert_eq(vim.api.nvim_buf_is_valid(old_bufnr), false, "closing wipes the base hunk buffer")
  assert_eq(vim.api.nvim_buf_is_valid(new_bufnr), false, "closing wipes the working hunk buffer")
  assert_eq(state.get_buffer(old_bufnr), nil, "closing detaches base state")
  assert_eq(state.get_buffer(new_bufnr), nil, "closing detaches working state")

  local second_old, second_new, second_old_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = source_win,
    loading = false,
    parsed = {
      lines = { "@@ -1 +1 @@", "-base content", "+working change" },
      hunks = { { header = "@@ -1 +1 @@", row = 1 } },
    },
    opts = {},
  }, { kind = "vsplit" })
  vim.api.nvim_win_close(second_old_win, true)
  assert_true(vim.wait(1000, function()
    return state.get_buffer(second_old) == nil and state.get_buffer(second_new) == nil
  end, 10), "closing either window cleans up the pair")
  assert_true(#vim.fn.win_findbuf(source_bufnr) > 0, "window-close cleanup restores the source buffer")
end
