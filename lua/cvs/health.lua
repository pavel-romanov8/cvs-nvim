local M = {}

function M.check()
  local health = vim.health or require("health")
  local caps = require("cvs.cvs.capabilities").detect()

  health.start("cvs.nvim")

  if caps.executable then
    health.ok(("Found CVS executable: %s"):format(caps.bin))
  else
    health.error(("CVS executable is not available: %s"):format(caps.bin))
  end

  if caps.has_vim_system then
    health.ok("vim.system is available")
  else
    health.error("vim.system is required for cvs.nvim")
  end
end

return M
