local M = {}

function M.detect()
  local config = require("cvs.config").get()
  local bin = config.cvs.bin

  return {
    bin = bin,
    executable = vim.fn.executable(bin) == 1,
    has_vim_system = vim.system ~= nil,
  }
end

return M
