local config = require("cvs.config")

local M = {}

local split_positions = {
  aboveleft = true,
  belowright = true,
  botright = true,
  leftabove = true,
  rightbelow = true,
  topleft = true,
}

local function split_command(kind, position)
  if kind == "left_vsplit" then
    kind = "vsplit"
    position = position or "leftabove"
  end

  local command = kind == "vsplit" and "vsplit" or "split"
  if split_positions[position] then
    return position .. " " .. command
  end
  return command
end

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
  local source_height = vim.api.nvim_win_get_height(0)
  local source_width = vim.api.nvim_win_get_width(0)

  if kind == "floating" then
    return open_floating(bufnr, opts)
  end

  if kind == "tab" then
    vim.cmd("tabnew")
  elseif kind == "left_vsplit" or kind == "vsplit" then
    vim.cmd(split_command(kind, opts.position))
  elseif kind == "split" then
    vim.cmd(split_command(kind, opts.position))
  else
    vim.cmd("enew")
  end

  vim.api.nvim_win_set_buf(0, bufnr)
  local winid = vim.api.nvim_get_current_win()

  if opts.width and (kind == "left_vsplit" or kind == "vsplit") then
    local width = opts.width < 1 and math.floor(source_width * opts.width) or opts.width
    pcall(vim.api.nvim_win_set_width, winid, math.max(1, width))
  end

  if opts.height and kind == "split" then
    local height = opts.height < 1 and math.floor(source_height * opts.height) or opts.height
    pcall(vim.api.nvim_win_set_height, winid, math.max(1, height))
  end

  return winid
end

return M
