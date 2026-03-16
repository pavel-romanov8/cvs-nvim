local M = {}

local initialized = false

local function call(module_name, method)
  return function(opts)
    return require(module_name)[method](opts or {})
  end
end

function M.setup(opts)
  require("cvs.config").setup(opts or {})

  if initialized then
    return
  end

  require("cvs.commands").setup()
  require("cvs.ui.highlights").setup()

  initialized = true
end

M.status = call("cvs.features.status.service", "open")
M.session = call("cvs.features.session.service", "open")
M.update = call("cvs.features.update.service", "run")
M.add = call("cvs.features.files.service", "add")
M.remove = call("cvs.features.files.service", "remove")
M.commit = call("cvs.features.commit.service", "open")
M.diff = call("cvs.features.diff.service", "open")
M.log = call("cvs.features.log.service", "open")
M.annotate = call("cvs.features.annotate.service", "open")
M.conflicts = call("cvs.features.conflicts.service", "open")

return M
