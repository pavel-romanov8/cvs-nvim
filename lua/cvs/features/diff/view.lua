local preview = require("cvs.ui.preview")

local M = {}

function M.open(context, command)
  return preview.open({
    "CVS Diff",
    "",
    ("Workspace: %s"):format(context.root_dir),
    ("Command: %s"):format(table.concat(command, " ")),
    "",
    "Diff rendering will land in this module.",
  }, {
    name = "cvs://diff",
    filetype = "diff",
  })
end

return M
