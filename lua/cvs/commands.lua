local M = {}

local initialized = false

local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
end

local function command_opts(args)
  return {
    path = args.args ~= "" and args.args or nil,
  }
end

function M.setup()
  if initialized then
    return
  end

  create("CVS", function(args)
    require("cvs").session(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the main CVS workspace view",
  })

  create("Cvs", function(args)
    require("cvs").status(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsStatus", function(args)
    require("cvs").status(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsUpdate", function(args)
    require("cvs").update(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Run or preview a CVS update workflow",
  })

  create("CvsAdd", function(args)
    require("cvs").add(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Add a file or directory to CVS",
  })

  create("CvsRemove", function(args)
    require("cvs").remove(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Remove a file or directory from CVS",
  })

  create("CvsCommit", function(args)
    require("cvs").commit(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS commit workflow",
  })

  create("CvsDiff", function(args)
    require("cvs").diff(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Diff a working file against its CVS base revision",
  })

  create("Cdiffsplit", function()
    require("cvs").diff({
      source_bufnr = vim.api.nvim_get_current_buf(),
      source_win = vim.api.nvim_get_current_win(),
    })
  end, {
    desc = "Diff the current file against its CVS base revision",
  })

  create("CvsLog", function(args)
    require("cvs").log(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS log workflow",
  })

  create("CvsAnnotate", function(args)
    require("cvs").annotate(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS annotate workflow",
  })

  create("CvsConflicts", function(args)
    require("cvs").conflicts(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS conflict workflow",
  })

  initialized = true
end

return M
