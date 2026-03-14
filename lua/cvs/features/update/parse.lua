local types = require("cvs.core.types")

local M = {}

local code_map = {
  U = types.status.updated,
  P = types.status.patched,
  M = types.status.modified,
  A = types.status.added,
  R = types.status.removed,
  C = types.status.conflict,
  ["?"] = types.status.unknown,
}

local function empty_summary()
  return {
    [types.status.updated] = 0,
    [types.status.patched] = 0,
    [types.status.modified] = 0,
    [types.status.added] = 0,
    [types.status.removed] = 0,
    [types.status.conflict] = 0,
    [types.status.unknown] = 0,
  }
end

local function ignored_message(line)
  return line:match("^cvs%s+update:%s+Updating%s+") ~= nil
    or line:match("^cvs%s+server:%s+Updating%s+") ~= nil
end

function M.parse(lines)
  local parsed = {
    items = {},
    messages = {},
    summary = empty_summary(),
    has_conflicts = false,
  }

  for _, raw in ipairs(lines or {}) do
    local line = vim.trim(raw)
    local code, path = line:match("^([%?A-Z])%s+(.+)$")

    if code and code_map[code] then
      local status = code_map[code]
      parsed.items[#parsed.items + 1] = {
        code = code,
        path = path,
        status = status,
      }
      parsed.summary[status] = parsed.summary[status] + 1
      if status == types.status.conflict then
        parsed.has_conflicts = true
      end
    elseif line ~= "" and not ignored_message(line) then
      parsed.messages[#parsed.messages + 1] = line
    end
  end

  return parsed
end

return M
