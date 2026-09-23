local M = {}

local function trim(value)
  return vim.trim(value or "")
end

-- CVS log separates revisions with a line of dashes and files with equals.
function M.parse(lines)
  local result = { entries = {}, symbols = {}, header = {}, messages = {} }
  local entry
  local in_symbols = false
  local in_description = false

  for _, line in ipairs(lines or {}) do
    if line:match("^=+$") then
      break
    elseif line:match("^%-+$") and #line >= 20 then
      entry = nil
    elseif line:match("^revision%s+[%d.]+%s*$") then
      local revision = line:match("^revision%s+([%d.]+)")
      entry = { revision = revision, message = {}, tags = {} }
      result.entries[#result.entries + 1] = entry
      in_symbols = false
      in_description = false
    elseif entry then
      if line:match("^branches:%s*") then
        entry.branches = trim(line:match("^branches:%s*(.*)"))
      elseif not entry.date then
        local date, author, state = line:match("^date:%s*(.-);%s*author:%s*(.-);%s*state:%s*([^;]+)")
        if date then
          entry.date = trim(date)
          entry.author = trim(author)
          entry.state = trim(state)
          entry.lines = line:match("lines:%s*([^;]+)")
          entry.branches = line:match("branches:%s*([^;]+)")
        else
          entry.message[#entry.message + 1] = line
        end
      else
        entry.message[#entry.message + 1] = line
      end
    elseif in_symbols then
      local name, revision = line:match("^%s+([^:%s]+):%s*([%d.]+)%s*$")
      if name then
        result.symbols[#result.symbols + 1] = { name = name, revision = revision }
      else
        in_symbols = false
      end
    elseif line:match("^symbolic names:%s*$") then
      in_symbols = true
    elseif line:match("^description:%s*$") then
      in_description = true
    elseif not in_description then
      local key, value = line:match("^([^:]+):%s*(.*)$")
      if key then
        result.header[trim(key)] = trim(value)
      end
    end
  end

  for _, item in ipairs(result.symbols) do
    for _, revision in ipairs(result.entries) do
      if item.revision == revision.revision then
        revision.tags[#revision.tags + 1] = item.name
      else
        -- CVS represents a branch symbol using a zero penultimate component
        -- (e.g. 1.2.0.2); branch revisions use 1.2.2.N.
        local branch = item.revision:match("^(.*)%.0%.(%d+)$")
        local number = item.revision:match("^.*%.0%.(%d+)$")
        if branch and vim.startswith(revision.revision, branch .. "." .. number .. ".") then
          revision.tags[#revision.tags + 1] = item.name .. " (branch)"
        end
      end
    end
  end

  for _, revision in ipairs(result.entries) do
    while #revision.message > 0 and revision.message[#revision.message] == "" do
      table.remove(revision.message)
    end
  end

  return result
end

-- CVS branch revisions end in their own sequence number. The first commit
-- on a branch has the branch point as its predecessor.
function M.predecessor(revision)
  local parts = vim.split(revision or "", ".", { plain = true })
  if #parts < 2 then
    return nil
  end
  local last = tonumber(parts[#parts])
  if not last then
    return nil
  end
  if last > 1 then
    parts[#parts] = tostring(last - 1)
  elseif #parts > 2 then
    table.remove(parts)
    table.remove(parts)
  else
    return nil
  end
  return table.concat(parts, ".")
end

return M
