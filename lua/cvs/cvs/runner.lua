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
    stdout_ends_with_newline = type(result.stdout) == "string" and vim.endswith(result.stdout, "\n"),
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
  }

  if opts.timeout ~= false then
    job_opts.timeout = opts.timeout or config.get().cvs.timeout_ms
  end

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

function M.stream(cmd, opts, handlers)
  if not vim.system then
    error("cvs.nvim requires vim.system")
  end

  opts = opts or {}
  handlers = handlers or {}

  local started_at = uv.hrtime()
  local stream_error
  local process
  local stderr_chunks = {}
  local stderr_bytes = 0
  local max_stderr_bytes = opts.max_stderr_bytes or 65536

  local function cancel()
    if process then
      M.cancel(process)
    end
  end

  local function consume(handler, data)
    if stream_error or not data or data == "" or not handler then
      return
    end

    local ok, err = pcall(handler, data)
    if not ok then
      stream_error = tostring(err)
      cancel()
    end
  end

  local job_opts = {
    cwd = opts.cwd,
    text = opts.text ~= false,
    stdin = opts.stdin,
    stdout = function(err, data)
      if err then
        stream_error = stream_error or tostring(err)
        cancel()
        return
      end
      consume(handlers.on_stdout, data)
    end,
    stderr = function(err, data)
      if err then
        stream_error = stream_error or tostring(err)
        cancel()
        return
      end

      if handlers.on_stderr then
        consume(handlers.on_stderr, data)
      elseif data and stderr_bytes < max_stderr_bytes then
        local remaining = max_stderr_bytes - stderr_bytes
        local chunk = data:sub(1, remaining)
        stderr_chunks[#stderr_chunks + 1] = chunk
        stderr_bytes = stderr_bytes + #chunk
      end
    end,
  }

  if opts.timeout ~= false then
    job_opts.timeout = opts.timeout or config.get().cvs.timeout_ms
  end

  process = vim.system(cmd, job_opts, function(result)
    local payload = {
      cmd = cmd,
      code = result.code or 0,
      signal = result.signal,
      stdout = {},
      stderr = split_output(table.concat(stderr_chunks)),
      stream_error = stream_error,
      cwd = opts.cwd,
      duration_ms = math.floor((uv.hrtime() - started_at) / 1000000),
    }

    vim.schedule(function()
      if handlers.on_complete then
        handlers.on_complete(payload)
      end
    end)
  end)

  return process
end

function M.cancel(process)
  if not process or not process.kill then
    return
  end

  pcall(process.kill, process, 15)
  vim.defer_fn(function()
    pcall(process.kill, process, 9)
  end, 1000)
end

return M
