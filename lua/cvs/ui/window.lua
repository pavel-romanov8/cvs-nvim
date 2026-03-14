local config = require("cvs.config")

local M = {}

local function open_floating(bufnr, opts)
  local ui = config.get().ui.floating
  local width = math.floor(vim.o.columns * (opts.width or ui.width))
  local height = math.floor((vim.o.lines - vim.o.cmdheight) * (opts.height or ui.height))
  local row = math.floor(((vim.o.lines - vim.o.cmdheight) - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or ui.border,
  })
end

function M.open(bufnr, opts)
  opts = opts or {}

  local kind = opts.kind or config.get().ui.default_kind

  if kind == "floating" then
    return open_floating(bufnr, opts)
  end

  if kind == "tab" then
    vim.cmd("tabnew")
  elseif kind == "split" then
    vim.cmd("split")
  elseif kind == "vsplit" then
    vim.cmd("vsplit")
  else
    vim.cmd("enew")
  end

  vim.api.nvim_win_set_buf(0, bufnr)
  return vim.api.nvim_get_current_win()
end

return M
