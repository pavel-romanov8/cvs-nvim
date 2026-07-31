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
  assert_true(commands.CvsStatus ~= nil, ":CvsStatus remains registered")

  local original = package.loaded.cvs
  local status_calls = {}
  local diff_opts
  package.loaded.cvs = {
    status = function(opts)
      status_calls[#status_calls + 1] = opts
    end,
    diff = function(opts)
      diff_opts = opts
    end,
  }

  vim.cmd("Cvs")
  vim.cmd("Cvs!")
  vim.cmd("Cdiffsplit")

  package.loaded.cvs = original
  assert_true(status_calls[1] ~= nil and status_calls[1].path == nil, ":Cvs defaults to the current workspace")
  assert_true(status_calls[1].force == nil, ":Cvs allows cached status")
  assert_true(status_calls[2] ~= nil and status_calls[2].force == true, ":Cvs! forces a fresh status")
  assert_true(diff_opts ~= nil and diff_opts.source_bufnr == vim.api.nvim_get_current_buf(), ":Cdiffsplit uses current file")
end
