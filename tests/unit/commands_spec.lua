local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  require("cvs.commands").setup()
  local commands = vim.api.nvim_get_commands({})

  assert_true(commands.Cvs ~= nil, ":Cvs is registered")
  assert_true(commands.CVS == nil, ":CVS is no longer registered")
  assert_true(commands.Cdiffsplit ~= nil, ":Cdiffsplit is registered")
  assert_true(commands.CvsDiff ~= nil, ":CvsDiff is registered")
  assert_true(commands.CvsStatus ~= nil, ":CvsStatus remains registered")

  local original = package.loaded.cvs
  local status_calls = {}
  local diff_calls = {}
  package.loaded.cvs = {
    status = function(opts)
      status_calls[#status_calls + 1] = opts
    end,
    diff = function(opts)
      diff_calls[#diff_calls + 1] = opts
    end,
  }

  vim.cmd("Cvs")
  vim.cmd("Cvs!")
  vim.cmd("vertical Cvs")
  vim.cmd("horizontal CvsStatus")
  vim.cmd("tab Cvs")
  vim.cmd("botright vertical Cvs")
  vim.cmd("CvsDiff")
  vim.cmd("CvsDiff!")
  vim.cmd("Cdiffsplit")
  vim.cmd("Cdiffsplit!")

  package.loaded.cvs = original
  assert_true(status_calls[1] ~= nil and status_calls[1].path == nil, ":Cvs defaults to the current workspace")
  assert_true(status_calls[1].force == nil, ":Cvs allows cached status")
  assert_true(status_calls[2] ~= nil and status_calls[2].force == true, ":Cvs! forces a fresh status")
  assert_true(status_calls[3].kind == "vsplit", ":vertical Cvs requests a vertical split")
  assert_true(status_calls[4].kind == "split", ":horizontal CvsStatus requests a horizontal split")
  assert_true(status_calls[5].kind == "tab", ":tab Cvs requests a tab")
  assert_true(status_calls[6].kind == "vsplit", "layout and placement modifiers can be combined")
  assert_true(status_calls[6].position == "botright", "split placement modifier is preserved")
  assert_true(diff_calls[1].stream == nil, ":CvsDiff uses the full diff view")
  assert_true(diff_calls[2].stream == true, ":CvsDiff! requests streamed hunks")
  assert_true(diff_calls[3].source_bufnr == vim.api.nvim_get_current_buf(), ":Cdiffsplit uses current file")
  assert_true(diff_calls[3].stream == nil, ":Cdiffsplit uses the full diff view")
  assert_true(diff_calls[4].stream == true, ":Cdiffsplit! requests streamed hunks")
  assert_true(diff_calls[4].kind == "vsplit", ":Cdiffsplit! opens hunks vertically")
end
