local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

function M.open(context, command, opts)
  local bufnr = ui_buffer.create({
    name = "cvs://annotate",
    filetype = "cvs-annotate",
  })

  ui_buffer.set_lines(bufnr, {
    "CVS Annotate",
    "",
    ("Workspace: %s"):format(context.root_dir),
    ("Command: %s"):format(table.concat(command, " ")),
    "",
    "Annotate parsing and rendering will land here.",
  })

  return bufnr, window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.annotate.kind,
  })
end

return M
