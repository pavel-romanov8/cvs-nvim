local config = require("cvs.config")
local state = require("cvs.core.state")
local diff_view = require("cvs.features.diff.view")

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
  }, { kind = "vsplit" })
  assert(vim.api.nvim_buf_get_lines(old_bufnr, 0, 1, false)[1] == "Loading CVS diff...",
    "paired diff opens before CVS completes")

  diff_view.update(old_bufnr, {
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = source_win,
    parsed = {
      lines = { "@@ -1 +1 @@", "-base content", "+working change" },
      hunks = { { header = "@@ -1 +1 @@", row = 1 } },
    },
    opts = {},
  })

  local old_lines = vim.api.nvim_buf_get_lines(old_bufnr, 0, -1, false)
  local new_lines = vim.api.nvim_buf_get_lines(new_bufnr, 0, -1, false)
  assert(old_lines[2] == "base content" and new_lines[2] == "working change",
    "unified hunks reconstruct base and working sides")
  assert(vim.wo[old_win].diff and vim.wo[new_win].diff
    and vim.wo[old_win].scrollbind and vim.wo[new_win].scrollbind,
    "paired windows use synchronized native diff")
  assert(vim.bo[old_bufnr].readonly and not vim.bo[old_bufnr].modifiable
    and vim.bo[new_bufnr].readonly and not vim.bo[new_bufnr].modifiable,
    "reconstructed hunk buffers are immutable")
  assert(vim.api.nvim_buf_get_lines(source_bufnr, 0, 1, false)[1] == "working change"
    and vim.bo[source_bufnr].modified, "streamed presentation never mutates the source buffer")

  diff_view.close(new_bufnr)
  assert(vim.api.nvim_win_get_buf(source_win) == source_bufnr,
    "closing the pair restores the original source window")
  assert(not vim.api.nvim_buf_is_valid(old_bufnr) and not vim.api.nvim_buf_is_valid(new_bufnr),
    "closing wipes both temporary diff buffers")

  local second_old, second_new, second_old_win = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    source_bufnr = source_bufnr,
    source_win = source_win,
    parsed = {
      lines = { "@@ -1 +1 @@", "-base content", "+working change" },
      hunks = { { header = "@@ -1 +1 @@", row = 1 } },
    },
    opts = {},
  }, { kind = "vsplit" })
  vim.api.nvim_win_close(second_old_win, true)
  assert(vim.wait(1000, function()
    return state.get_buffer(second_old) == nil and state.get_buffer(second_new) == nil
  end, 10), "closing either window cleans up the paired state")
end
