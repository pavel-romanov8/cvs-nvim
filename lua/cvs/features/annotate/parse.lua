local M = {}

local function parse_meta(meta)
  local author, date = vim.trim(meta):match("^(%S+)%s+(.+)$")
  if not author then
    return vim.trim(meta), ""
  end

  return author, vim.trim(date)
end

function M.parse(lines)
  local entries = {}
  local messages = {}

  for _, line in ipairs(lines or {}) do
    local revision, meta, text = line:match("^(%S+)%s+%((.-)%)%:%s?(.*)$")
    if revision then
      local author, date = parse_meta(meta)
      entries[#entries + 1] = {
        line_number = #entries + 1,
        revision = revision,
        author = author,
        date = date,
        text = text,
      }
    elseif line ~= "" and not line:match("^Annotations for ") and not line:match("^%*+$") then
      messages[#messages + 1] = line
    end
  end

  return {
    entries = entries,
    messages = messages,
  }
end

return M
