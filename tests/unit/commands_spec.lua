return function()
  require("cvs.commands").setup()
  local commands = vim.api.nvim_get_commands({})
  assert(commands.Cvs and commands.CvsDiff and commands.Cdiffsplit and commands.CvsLog and commands.CvsRevert,
    "public CVS commands are registered")

  local original = package.loaded.cvs
  local calls = {}
  package.loaded.cvs = setmetatable({}, {
    __index = function(_, method)
      return function(opts)
        calls[#calls + 1] = { method = method, opts = opts }
      end
    end,
  })

  vim.cmd("Cvs!")
  vim.cmd("CvsDiff!")
  vim.cmd("vertical CvsLog")
  vim.cmd("CvsLog!")
  vim.cmd("CvsRevert ABC123")
  package.loaded.cvs = original

  assert(calls[1].method == "status" and calls[1].opts.force, ":Cvs! forces workspace status")
  assert(calls[2].method == "diff" and calls[2].opts.stream, ":CvsDiff! selects streamed hunks")
  assert(calls[3].method == "log" and calls[3].opts.kind == "vsplit", "Ex modifiers reach :CvsLog")
  assert(calls[4].method == "log" and calls[4].opts.force, ":CvsLog! selects the workspace root")
  assert(calls[5].method == "revert" and calls[5].opts.commit_id == "ABC123",
    ":CvsRevert forwards its commit ID")
end
