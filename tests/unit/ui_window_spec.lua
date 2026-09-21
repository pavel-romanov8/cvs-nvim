local window = require("cvs.ui.window")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")

  local source_win = vim.api.nvim_get_current_win()
  local source_width = vim.api.nvim_win_get_width(source_win)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = window.open(bufnr, {
    kind = "vsplit",
    position = "aboveleft",
    width = 0.4,
  })

  assert_eq(vim.api.nvim_win_get_width(winid), math.floor(source_width * 0.4), "fractional vertical width")
  assert_true(
    vim.api.nvim_win_get_position(winid)[2] < vim.api.nvim_win_get_position(source_win)[2],
    "aboveleft places the new vertical split to the left"
  )

  vim.api.nvim_win_close(winid, true)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end
