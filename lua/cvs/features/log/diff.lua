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

local function contents_diff(output, ends_with_newline, reverse)
  local contents = table.concat(output, "\n")
  if ends_with_newline or (ends_with_newline == nil and #output > 0) then
    contents = contents .. "\n"
  end
  if contents:find("\0", 1, true) then
    return nil, "Binary file contents cannot be diffed."
  end
  local old = reverse and contents or ""
  local new = reverse and "" or contents
  return vim.split(vim.diff(old, new, { result_type = "unified", ctxlen = 3 }), "\n", {
    plain = true, trimempty = true,
  })
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
      local generated, generate_err = contents_diff(output, result.stdout_ends_with_newline, false)
      if not generated then
        callback(nil, generate_err)
        return
      end
      output = generated
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

-- Collect the inverse of one file revision. The normal case compares the bad
-- revision to its predecessor. An initial revision is compared to an empty
-- file so reverting an add can still be reviewed before removal.
function M.collect_reverse(request, revision, predecessor, callback)
  local command = predecessor
    and cmd.revision_diff({ path = request.path, from = revision, to = predecessor })
    or cmd.base({ path = request.path, revision = revision })

  return runner.run(command, { cwd = request.cwd, timeout = false }, function(result)
    if (result.signal or 0) ~= 0 or result.code > (predecessor and 1 or 0)
      or (result.code ~= 0 and #result.stdout == 0 and #result.stderr > 0) then
      callback(nil, result.stderr[1] or result.stdout[1] or ("CVS exited with code %d"):format(result.code))
      return
    end

    local output = result.stdout
    if not predecessor then
      local generated, generate_err = contents_diff(output, result.stdout_ends_with_newline, true)
      if not generated then
        callback(nil, generate_err)
        return
      end
      output = generated
    end
    local parsed = parse_output(output, result.stdout_ends_with_newline)
    if parsed.error then
      callback(nil, parsed.error)
    else
      callback({ from = revision, to = predecessor, parsed = parsed })
    end
  end)
end

-- A deleted revision is represented by an absent working file. Preview its
-- restoration as additions from an empty file to the last live revision.
function M.collect_restore(request, revision, callback)
  local command = cmd.base({ path = request.path, revision = revision })
  return runner.run(command, { cwd = request.cwd, timeout = false }, function(result)
    if (result.signal or 0) ~= 0 or result.code ~= 0 then
      callback(nil, result.stderr[1] or result.stdout[1] or ("CVS exited with code %d"):format(result.code))
      return
    end
    local output, generate_err = contents_diff(result.stdout, result.stdout_ends_with_newline, false)
    if not output then
      callback(nil, generate_err)
      return
    end
    local parsed = parse_output(output, result.stdout_ends_with_newline)
    if parsed.error then
      callback(nil, parsed.error)
    else
      callback({ from = nil, to = revision, parsed = parsed })
    end
  end)
end

return M
