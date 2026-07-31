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

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_win_set_buf(0, source_bufnr)
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "working change" })
  vim.bo[source_bufnr].filetype = "lua"
  vim.bo[source_bufnr].modified = true

  local base_bufnr, base_win, source_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = vim.api.nvim_get_current_win(),
    result = {
      stdout = { "base content" },
    },
  })

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "diff view has two windows")
  assert_true(vim.wo[base_win].diff, "base window enables diff mode")
  assert_true(vim.wo[source_win].diff, "source window enables diff mode")
  assert_eq(vim.bo[base_bufnr].readonly, true, "base buffer is read-only")
  assert_eq(vim.bo[base_bufnr].filetype, "lua", "base buffer keeps the source filetype")
  assert_eq(vim.api.nvim_buf_get_lines(base_bufnr, 0, -1, false)[1], "base content", "base content is rendered")
  assert_eq(
    vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)[1],
    "working change",
    "working buffer content is preserved"
  )
  assert_true(vim.bo[source_bufnr].modified, "working buffer remains modified")

  local next_base, next_base_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.8",
    source_bufnr = source_bufnr,
    source_win = source_win,
    result = {
      stdout = { "new base" },
      stdout_ends_with_newline = false,
    },
  })

  assert_eq(vim.api.nvim_buf_is_valid(base_bufnr), false, "reopening replaces the previous base")
  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "reopening does not leave an extra window")
  assert_true(vim.wo[source_win].diff, "replacing the base keeps source diff mode")
  assert_eq(vim.bo[next_base].endofline, false, "base buffer preserves a missing final newline")

  vim.api.nvim_win_close(next_base_win, true)
  assert_eq(vim.api.nvim_buf_is_valid(next_base), false, "closing the base window wipes its buffer")
  assert_eq(vim.wo[source_win].diff, false, "closing the base buffer disables source diff mode")

  local other_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(other_bufnr, 0, -1, false, { "other diff" })
  local other_win = vim.api.nvim_win_call(source_win, function()
    vim.cmd("vsplit")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, other_bufnr)
    return winid
  end)
  vim.api.nvim_win_call(source_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(other_win, function()
    vim.cmd("diffthis")
  end)

  local external_base, external_base_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.9",
    source_bufnr = source_bufnr,
    source_win = source_win,
    result = {
      stdout = { "external diff base" },
    },
  })
  vim.api.nvim_win_close(external_base_win, true)
  assert_eq(vim.api.nvim_buf_is_valid(external_base), false, "external diff base is wiped")
  assert_true(vim.wo[source_win].diff, "closing the base preserves pre-existing source diff mode")
  assert_true(vim.wo[other_win].diff, "closing the base preserves the existing diff partner")
  vim.api.nvim_win_close(other_win, true)
  vim.api.nvim_win_call(source_win, function()
    vim.cmd("diffoff")
  end)
end
