local cmd = require("cvs.cvs.cmd")
local config = require("cvs.config")
local parser = require("cvs.features.diff.parse")
local log = require("cvs.features.log.parse")
local runner = require("cvs.cvs.runner")

local M = {}

local function parse_output(lines, ends_with_newline)
  local limits = config.get().diff
  local text = table.concat(lines, "\n")
  if ends_with_newline and #lines > 0 then
    text = text .. "\n"
  end
  local state = parser.new({ max_bytes = limits.max_bytes, max_lines = limits.max_lines })
  state:feed(text)
  return state:finish()
end

function M.collect(request, revision, callback)
  local previous = log.predecessor(revision)
  local command = previous
    and cmd.revision_diff({ path = request.path, from = previous, to = revision })
    or cmd.base({ path = request.path, revision = revision })

  local process = runner.run(command, { cwd = request.cwd, timeout = false }, function(result)
    if (result.signal or 0) ~= 0 or result.code > (previous and 1 or 0)
      or (result.code ~= 0 and #result.stdout == 0 and #result.stderr > 0) then
      callback(nil, result.stderr[1] or result.stdout[1] or ("CVS exited with code %d"):format(result.code))
      return
    end

    local output = result.stdout
    if not previous then
      local contents = table.concat(output, "\n")
      if result.stdout_ends_with_newline or (result.stdout_ends_with_newline == nil and #output > 0) then
        contents = contents .. "\n"
      end
      if contents:find("\0", 1, true) then
        callback(nil, "Binary file contents cannot be diffed.")
        return
      end
      output = vim.split(vim.diff("", contents, { result_type = "unified", ctxlen = 3 }), "\n", {
        plain = true, trimempty = true,
      })
    end

    local parsed = parse_output(output, result.stdout_ends_with_newline)
    if parsed.error then
      callback(nil, parsed.error)
    elseif #parsed.lines == 0 and #parsed.messages > 0 and not parsed.binary then
      callback(nil, parsed.messages[1])
    else
      callback({ from = previous, to = revision, parsed = parsed })
    end
  end)
  return process
end

return M
