local M = {}

function M.parse(paths)
  local items = {}

  for _, path in ipairs(paths or {}) do
    items[#items + 1] = {
      backup = path,
    }
  end

  return items
end

return M
