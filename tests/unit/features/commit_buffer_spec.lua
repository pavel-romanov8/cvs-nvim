local buffer = require("cvs.features.commit.buffer")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local lines = {
    "Subject line",
    "",
    "Body line",
    "# Write the CVS commit message above.",
    "# Status: editing",
  }

  local message_lines = buffer._extract_message_lines(lines)
  assert_eq(#message_lines, 3, "message line count")
  assert_eq(message_lines[1], "Subject line", "subject is preserved")
  assert_eq(message_lines[2], "", "blank body separator is preserved")
  assert_eq(message_lines[3], "Body line", "body is preserved")

  local rendered = buffer._render_lines({
    message_lines = { "" },
    workspace = { root_dir = "/tmp/work" },
    scope_label = "2 selected files",
    phase = "editing",
    files = { "pkg/one.lua", "pkg/two.lua" },
    validation = { status = "checking", message = "checking CVS state..." },
  })
  local text = table.concat(rendered, "\n")
  assert_eq(text:find("# Selected Files (2):", 1, true) ~= nil, true, "selected file heading is rendered")
  assert_eq(text:find("#   pkg/one.lua", 1, true) ~= nil, true, "first selected file is rendered")
  assert_eq(text:find("#   pkg/two.lua", 1, true) ~= nil, true, "second selected file is rendered")
  assert_eq(text:find("# Validation: checking CVS state...", 1, true) ~= nil, true, "validation is rendered")

  local original_bufnr = vim.api.nvim_get_current_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, rendered)
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "Draft message" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  buffer.update_validation(bufnr, { status = "ready", message = "ready" })
  local updated = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  assert_eq(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1], "Draft message", "validation preserves the draft")
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1, "validation preserves the cursor row")
  assert_eq(updated:find("# Validation: ready", 1, true) ~= nil, true, "validation updates in place")
  vim.api.nvim_win_set_buf(0, original_bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end
