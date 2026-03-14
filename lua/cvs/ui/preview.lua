local buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

function M.open(lines, opts)
  opts = opts or {}

  local bufnr = buffer.create({
    name = opts.name or "cvs://preview",
    filetype = opts.filetype or "cvs",
  })

  buffer.set_lines(bufnr, lines or {})
  buffer.lock(bufnr)

  return bufnr, window.open(bufnr, {
    kind = opts.kind or "floating",
    width = opts.width,
    height = opts.height,
    border = opts.border,
  })
end

return M
