local util = require("cvs.core.util")

local M = {}

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
  return M.parse_lines(util.read_file(path) or {})
end

return M
