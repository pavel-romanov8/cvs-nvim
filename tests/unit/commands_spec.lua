local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  require("cvs.commands").setup()
  local commands = vim.api.nvim_get_commands({})

  assert_true(commands.Cvs ~= nil, ":Cvs is registered")
  assert_true(commands.Cdiffsplit ~= nil, ":Cdiffsplit is registered")
  assert_true(commands.CvsStatus ~= nil, ":CvsStatus remains registered")

  local original = package.loaded.cvs
  local status_opts
  local diff_opts
  package.loaded.cvs = {
    status = function(opts)
      status_opts = opts
    end,
    diff = function(opts)
      diff_opts = opts
    end,
  }

  vim.cmd("Cvs")
  vim.cmd("Cdiffsplit")

  package.loaded.cvs = original
  assert_true(status_opts ~= nil and status_opts.path == nil, ":Cvs defaults to the current workspace")
  assert_true(diff_opts ~= nil and diff_opts.source_bufnr == vim.api.nvim_get_current_buf(), ":Cdiffsplit uses current file")
end
