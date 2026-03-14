local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

function M.open(context, command, opts)
  local bufnr = ui_buffer.create({
    name = "cvs://commit",
    filetype = "cvscommit",
  })

  ui_buffer.set_lines(bufnr, {
    "CVS Commit",
    "",
    ("Workspace: %s"):format(context.root_dir),
    ("Command: %s"):format(table.concat(command, " ")),
    "",
    "Write the commit buffer workflow here next.",
  })

  return bufnr, window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.commit.kind,
  })
end

return M
