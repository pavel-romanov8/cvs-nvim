local M = {}

function M.build(parsed)
  parsed = parsed or {}

  local old_lines = {}
  local new_lines = {}
  local lines = parsed.lines or {}
  local hunks = parsed.hunks or {}

  for index, hunk in ipairs(hunks) do
    local last_row = hunks[index + 1] and hunks[index + 1].row - 1 or #lines
    old_lines[#old_lines + 1] = hunk.header
    new_lines[#new_lines + 1] = hunk.header
    local previous_prefix

    for row = hunk.row + 1, last_row do
      local line = lines[row]
      local prefix = line:sub(1, 1)
      local text = line:sub(2)

      if prefix == " " then
        old_lines[#old_lines + 1] = text
        new_lines[#new_lines + 1] = text
      elseif prefix == "-" then
        old_lines[#old_lines + 1] = text
      elseif prefix == "+" then
        new_lines[#new_lines + 1] = text
      elseif prefix == "\\" then
        if previous_prefix == "-" then
          old_lines[#old_lines + 1] = line
        elseif previous_prefix == "+" then
          new_lines[#new_lines + 1] = line
        else
          old_lines[#old_lines + 1] = line
          new_lines[#new_lines + 1] = line
        end
      end
      previous_prefix = prefix
    end
  end

  return {
    old_lines = old_lines,
    new_lines = new_lines,
  }
end

return M
