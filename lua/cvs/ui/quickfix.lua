local M = {}

function M.set(items, title, should_open)
  vim.fn.setqflist({}, " ", {
    title = title,
    items = items,
  })

  if should_open then
    vim.cmd("copen")
  end
end

return M
