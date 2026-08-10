local M = {}

local function hunk_counts(line)
  local old_count, new_count = line:match("^@@ %-%d+,?(%d*) %+%d+,?(%d*) @@")
  if old_count == nil then
    return nil, nil
  end

  return tonumber(old_count ~= "" and old_count or "1"), tonumber(new_count ~= "" and new_count or "1")
end

local function is_preamble(line)
  return vim.startswith(line, "Index:")
    or line:match("^=+$") ~= nil
    or vim.startswith(line, "RCS file:")
    or vim.startswith(line, "retrieving revision")
    or vim.startswith(line, "diff ")
    or vim.startswith(line, "--- ")
    or vim.startswith(line, "+++ ")
end

function M.new(opts)
  opts = opts or {}

  local max_bytes = opts.max_bytes
  local max_lines = opts.max_lines
  local parsed = {
    lines = {},
    hunks = {},
    messages = {},
    truncated = false,
  }
  local pending = ""
  local byte_count = 0
  local old_remaining
  local new_remaining
  local accept_marker = false

  local function add_line(line)
    if max_lines and max_lines > 0 and #parsed.lines + #parsed.messages >= max_lines then
      parsed.truncated = true
      parsed.truncation_reason = "lines"
      return false
    end

    parsed.lines[#parsed.lines + 1] = line
    return true
  end

  local function add_message(line)
    if max_lines and max_lines > 0 and #parsed.lines + #parsed.messages >= max_lines then
      parsed.truncated = true
      parsed.truncation_reason = "lines"
      return false
    end

    parsed.messages[#parsed.messages + 1] = line
    return true
  end

  local function process_line(line)
    line = line:gsub("\r$", "")
    local old_count, new_count = hunk_counts(line)
    if old_count then
      if old_remaining ~= nil then
        parsed.error = "incomplete unified diff hunk before the next hunk header"
      end
      if not add_line(line) then
        return
      end
      parsed.hunks[#parsed.hunks + 1] = {
        header = line,
        row = #parsed.lines,
      }
      old_remaining = old_count
      new_remaining = new_count
      accept_marker = old_count == 0 and new_count == 0
      return
    end

    if old_remaining ~= nil then
      if not add_line(line) then
        return
      end

      local prefix = line:sub(1, 1)
      if prefix == " " then
        old_remaining = math.max(0, old_remaining - 1)
        new_remaining = math.max(0, new_remaining - 1)
      elseif prefix == "-" then
        old_remaining = math.max(0, old_remaining - 1)
      elseif prefix == "+" then
        new_remaining = math.max(0, new_remaining - 1)
      end

      if old_remaining == 0 and new_remaining == 0 then
        old_remaining = nil
        new_remaining = nil
        accept_marker = true
      end
      return
    end

    if accept_marker and vim.startswith(line, "\\ No newline at end of file") then
      add_line(line)
      return
    end
    accept_marker = false

    if line:match("^Binary files .+ differ$") or line:match("^Files .+ differ$") then
      parsed.binary = true
      add_message(line)
    elseif line ~= "" and not is_preamble(line) then
      add_message(line)
    end
  end

  local parser = {}

  function parser:feed(chunk)
    if parsed.truncated or not chunk or chunk == "" then
      return
    end

    if max_bytes and max_bytes > 0 and byte_count + #chunk > max_bytes then
      local remaining = math.max(0, max_bytes - byte_count)
      chunk = chunk:sub(1, remaining)
      parsed.truncated = true
      parsed.truncation_reason = "bytes"
    end
    byte_count = byte_count + #chunk

    local text = pending .. chunk
    local start = 1
    while true do
      local newline = text:find("\n", start, true)
      if not newline then
        pending = text:sub(start)
        break
      end

      process_line(text:sub(start, newline - 1))
      if parsed.truncated and parsed.truncation_reason == "lines" then
        pending = ""
        break
      end
      start = newline + 1
    end
  end

  function parser:finish()
    if not parsed.truncated and pending ~= "" then
      process_line(pending)
    end
    pending = ""
    if old_remaining ~= nil and not parsed.truncated then
      parsed.error = "incomplete unified diff hunk at end of output"
    end
    parsed.byte_count = byte_count
    return parsed
  end

  return parser
end

function M.lines(lines, opts)
  local parser = M.new(opts)
  parser:feed(table.concat(lines or {}, "\n"))
  return parser:finish()
end

return M
