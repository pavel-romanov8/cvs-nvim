local cmd = require("cvs.cvs.cmd")

local M = {}

function M.add(opts)
  return cmd.add(opts or {})
end

function M.remove(opts)
  return cmd.remove(opts or {})
end

return M
