local M = {}

function M.section(lines, title)
  if #lines > 0 and lines[#lines] ~= "" then
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = title
  lines[#lines + 1] = string.rep("-", #title)

  return lines
end

function M.key_values(lines, items)
  for _, item in ipairs(items or {}) do
    lines[#lines + 1] = ("%s: %s"):format(item[1], item[2] or "")
  end

  return lines
end

return M
