local preview = require("cvs.ui.preview")

local M = {}

function M.open(context, conflicts)
  local lines = {
    "CVS Conflicts",
    "",
    ("Workspace: %s"):format(context.root_dir),
    "",
  }

  if #conflicts == 0 then
    lines[#lines + 1] = "No CVS conflict backup files were detected."
  else
    lines[#lines + 1] = "Detected backup files:"
    lines[#lines + 1] = ""
    for _, conflict in ipairs(conflicts) do
      lines[#lines + 1] = conflict.backup
    end
  end

  return preview.open(lines, {
    name = "cvs://conflicts",
    filetype = "cvs",
  })
end

return M
