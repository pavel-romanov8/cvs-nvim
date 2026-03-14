local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local util = require("cvs.core.util")

local M = {}

function M.open(opts)
  local workspace, err = context.detect(opts.path)
  if not workspace then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return require("cvs.features.annotate.buffer").open(workspace, cmd.annotate(opts), opts)
end

return M
