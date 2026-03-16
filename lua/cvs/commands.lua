local M = {}

local initialized = false

local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
end

function M.setup()
  if initialized then
    return
  end

  create("Cvs", function(args)
    require("cvs").session({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS commit session view",
  })

  create("CvsStatus", function(args)
    require("cvs").status({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsUpdate", function(args)
    require("cvs").update({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Run or preview a CVS update workflow",
  })

  create("CvsAdd", function(args)
    require("cvs").add({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Add a file or directory to CVS",
  })

  create("CvsRemove", function(args)
    require("cvs").remove({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Remove a file or directory from CVS",
  })

  create("CvsCommit", function(args)
    require("cvs").commit({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS commit workflow",
  })

  create("CvsDiff", function(args)
    require("cvs").diff({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS diff workflow",
  })

  create("CvsLog", function(args)
    require("cvs").log({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS log workflow",
  })

  create("CvsAnnotate", function(args)
    require("cvs").annotate({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS annotate workflow",
  })

  create("CvsConflicts", function(args)
    require("cvs").conflicts({ path = args.args })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS conflict workflow",
  })

  initialized = true
end

return M
