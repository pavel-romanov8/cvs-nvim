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
  vim.bo[source_bufnr].modified = true

  local bufnr, winid = diff_view.open({
    target_path = "/tmp/file.lua",
    revision = "1.7",
    loading = false,
    parsed = {
      lines = {
        "@@ -1 +1 @@",
        "-base content",
        "+working change",
      },
    },
    opts = {},
  }, {
    kind = "vsplit",
  })

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "diff view opens in the requested split")
  assert_eq(vim.api.nvim_win_get_buf(winid), bufnr, "diff window displays the hunk buffer")
  assert_eq(vim.bo[bufnr].filetype, "diff", "diff buffer uses unified diff syntax")
  assert_eq(vim.bo[bufnr].readonly, true, "diff buffer is read-only")
  assert_eq(vim.bo[bufnr].modifiable, false, "diff buffer is not modifiable")
  assert_eq(vim.bo[bufnr].undolevels, -1, "diff buffer does not retain undo history")
  assert_eq(state.get_buffer(bufnr).kind, "diff", "diff state is attached")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_eq(lines[1], "@@ -1 +1 @@", "diff starts at the changed hunk")
  assert_eq(lines[3], "+working change", "diff renders the working line")
  assert_eq(vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)[1], "working change", "source is untouched")
  assert_true(vim.bo[source_bufnr].modified, "source remains modified")

  vim.api.nvim_set_current_win(winid)
  assert_eq(vim.fn.maparg("]c", "n", false, true).desc, "Go to next CVS diff hunk", "next-hunk mapping")
  assert_eq(vim.fn.maparg("[c", "n", false, true).desc, "Go to previous CVS diff hunk", "previous-hunk mapping")
  assert_eq(vim.fn.maparg("q", "n", false, true).desc, "Close CVS diff", "close mapping")

  diff_view.update(bufnr, {
    target_path = "/tmp/file.lua",
    revision = "1.7",
    loading = false,
    source_modified = true,
    parsed = {
      lines = {},
      messages = {},
    },
    opts = {},
  })
  lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_eq(lines[1], "Unsaved buffer changes are not included in this CVS diff.", "unsaved changes are explicit")
  assert_eq(lines[3], "No changes.", "clean diff has an explicit state")

  diff_view.update(bufnr, {
    target_path = "/tmp/file.lua",
    revision = "1.7",
    loading = false,
    parsed = {
      lines = {},
      messages = {},
      truncated = true,
      truncation_reason = "bytes",
    },
    opts = {},
  })
  lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_true(lines[1] ~= "No changes.", "truncated output is not reported as clean")
  assert_true(lines[#lines]:find("configured bytes limit", 1, true) ~= nil, "truncation reason is rendered")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert_eq(state.get_buffer(bufnr), nil, "wiping the diff detaches its state")
end
