local uv = vim.uv or vim.loop

local config = require("cvs.config")

local M = {}

local function split_output(text)
  if text == nil or text == "" then
    return {}
  end

  local lines = vim.split(text, "\n", { plain = true, trimempty = false })
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end

  return lines
end

local function complete(result, cmd, cwd, started_at)
  return {
    cmd = cmd,
    code = result.code or 0,
    signal = result.signal,
    stdout = split_output(result.stdout),
    stderr = split_output(result.stderr),
    cwd = cwd,
    duration_ms = math.floor((uv.hrtime() - started_at) / 1000000),
  }
end

function M.run(cmd, opts, callback)
  if not vim.system then
    error("cvs.nvim requires vim.system")
  end

  opts = opts or {}

  local started_at = uv.hrtime()
  local job_opts = {
    cwd = opts.cwd,
    text = true,
    stdin = opts.stdin,
    timeout = opts.timeout or config.get().cvs.timeout_ms,
  }

  if callback then
    return vim.system(cmd, job_opts, function(result)
      local payload = complete(result, cmd, opts.cwd, started_at)
      vim.schedule(function()
        callback(payload)
      end)
    end)
  end

  return complete(vim.system(cmd, job_opts):wait(), cmd, opts.cwd, started_at)
end

return M
