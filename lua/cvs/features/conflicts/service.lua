local context = require("cvs.cvs.context")
local detect = require("cvs.features.conflicts.detect")
local errors = require("cvs.core.errors")
local parse = require("cvs.features.conflicts.parse")
local util = require("cvs.core.util")

local M = {}

function M.open(opts)
  local workspace, err = context.detect(opts.path)
  if not workspace then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local conflicts = parse.parse(detect.scan(workspace.root_dir))
  return require("cvs.features.conflicts.view").open(workspace, conflicts, opts)
end

return M
