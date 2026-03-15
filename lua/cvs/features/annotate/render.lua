local M = {}

local function truncate(text, width)
  if width <= 0 then
    return ""
  end

  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  if width == 1 then
    return "~"
  end

  return text:sub(1, width - 1) .. "~"
end

local function pad(text, width)
  local value = truncate(text, width)
  local display_width = vim.fn.strdisplaywidth(value)

  if display_width >= width then
    return value
  end

  return value .. string.rep(" ", width - display_width)
end

function M.line(entry, opts)
  opts = opts or {}

  local author = pad(entry.author or "-", opts.author_width or 12)
  local date = entry.date or "-"

  return ("%s | %s"):format(author, date)
end

function M.lines(entries, opts)
  opts = opts or {}

  local lines = {}
  local line_count = math.max(opts.line_count or 0, #(entries or {}))

  for index = 1, line_count do
    local entry = entries and entries[index]
    lines[index] = entry and M.line(entry, opts) or ""
  end

  return lines
end

return M
