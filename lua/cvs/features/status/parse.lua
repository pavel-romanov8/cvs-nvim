local types = require("cvs.core.types")

local M = {}

local code_map = {
  M = types.status.modified,
  A = types.status.added,
  R = types.status.removed,
  C = types.status.conflict,
  P = types.status.patched,
  U = types.status.updated,
  ["?"] = types.status.unknown,
}

function M.parse(lines)
  local files = {}
  local messages = {}

  for _, line in ipairs(lines or {}) do
    local code, path = line:match("^([%?A-Z])%s+(.+)$")
    if code and code_map[code] then
      files[#files + 1] = {
        code = code,
        path = path,
        status = code_map[code],
      }
    elseif line ~= "" then
      messages[#messages + 1] = line
    end
  end

  return {
    files = files,
    messages = messages,
  }
end

return M
