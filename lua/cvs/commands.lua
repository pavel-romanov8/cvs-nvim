local M = {}

local initialized = false

local function resolve_path(raw)
  if raw == nil or raw == "" then
    return nil
  end

  return vim.fn.expand(raw)
end

local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
end

function M.setup()
  if initialized then
    return
  end

  create("CvsStatus", function(args)
    require("cvs").status({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsUpdate", function(args)
    require("cvs").update({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Run or preview a CVS update workflow",
  })

  create("CvsCommit", function(args)
    require("cvs").commit({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS commit workflow",
  })

  create("CvsDiff", function(args)
    require("cvs").diff({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS diff workflow",
  })

  create("CvsLog", function(args)
    require("cvs").log({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS log workflow",
  })

  create("CvsAnnotate", function(args)
    require("cvs").annotate({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS annotate workflow",
  })

  create("CvsConflicts", function(args)
    require("cvs").conflicts({ path = resolve_path(args.args) })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS conflict workflow",
  })

  initialized = true
end

return M
