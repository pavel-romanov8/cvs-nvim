local util = require("cvs.core.util")

local M = {}

function M.valid_revision(revision)
  if not revision or revision == "0" then
    return false
  end

  local parts = vim.split(revision, ".", { plain = true, trimempty = false })
  if #parts < 2 then
    return false
  end

  for _, part in ipairs(parts) do
    if not part:match("^%d+$") then
      return false
    end
  end

  return true
end

function M.parse_line(line)
  if line == nil or line == "" then
    return nil
  end

  local parts = vim.split(line, "/", { plain = true, trimempty = false })

  if vim.startswith(line, "D/") then
    return {
      kind = "directory",
      name = parts[2],
      revision = parts[3],
      raw = line,
    }
  end

  if vim.startswith(line, "/") then
    return {
      kind = "file",
      name = parts[2],
      revision = parts[3],
      timestamp = parts[4],
      options = parts[5],
      tag = parts[6],
      raw = line,
    }
  end

  return {
    kind = "meta",
    raw = line,
  }
end

function M.parse_lines(lines)
  local entries = {}

  for _, line in ipairs(lines or {}) do
    local entry = M.parse_line(line)
    if entry then
      entries[#entries + 1] = entry
    end
  end

  return entries
end

function M.load(path)
  local loaded = M.parse_lines(util.read_file(path) or {})

  for _, line in ipairs(util.read_file(path .. ".Log") or {}) do
    local action, raw = line:match("^(.) (.*)$")
    local entry = M.parse_line(raw)

    if action == "A" and entry then
      loaded[#loaded + 1] = entry
    elseif action == "R" and entry then
      for index, current in ipairs(loaded) do
        if current.raw == entry.raw then
          table.remove(loaded, index)
          break
        end
      end
    end
  end

  return loaded
end

function M.working_revision(target_path)
  local target_name = vim.fs.basename(target_path)
  local entries_path = util.path_join(vim.fs.dirname(target_path), "CVS", "Entries")

  for _, entry in ipairs(M.load(entries_path)) do
    if entry.kind == "file"
      and entry.name == target_name
      and M.valid_revision(entry.revision)
    then
      return entry.revision
    end
  end

  return nil
end

return M
