local full_view = require("cvs.features.diff.full_view")

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

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_win_set_buf(0, source_bufnr)
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "working change" })
  vim.bo[source_bufnr].filetype = "lua"
  vim.bo[source_bufnr].modified = true

  local base_bufnr, base_win, source_win = full_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = vim.api.nvim_get_current_win(),
    result = {
      stdout = { "base content" },
      stdout_ends_with_newline = true,
    },
  })

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "full diff has two windows")
  assert_true(vim.wo[base_win].diff, "base window enables native diff")
  assert_true(vim.wo[source_win].diff, "source window enables native diff")
  assert_eq(vim.bo[base_bufnr].readonly, true, "base buffer is read-only")
  assert_eq(vim.bo[base_bufnr].filetype, "lua", "base keeps the source filetype")
  assert_eq(vim.bo[base_bufnr].undolevels, -1, "base does not retain undo history")
  assert_eq(vim.api.nvim_buf_get_lines(base_bufnr, 0, -1, false)[1], "base content", "base content is loaded")
  assert_eq(vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)[1], "working change", "working content is preserved")
  assert_true(vim.bo[source_bufnr].modified, "working buffer remains modified")

  vim.api.nvim_win_close(base_win, true)
  assert_eq(vim.api.nvim_buf_is_valid(base_bufnr), false, "closing the full diff wipes its base")
  assert_eq(vim.wo[source_win].diff, false, "closing the full diff disables owned source diff mode")
end
