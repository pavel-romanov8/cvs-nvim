local render = require("cvs.ui.render")

local M = {}

function M.lines(snapshot)
  local lines = { "CVS Status" }

  render.section(lines, "Workspace")
  render.key_values(lines, {
    { "Root Dir", snapshot.workspace.root_dir },
    { "CVS Root", snapshot.workspace.cvs_root or "-" },
    { "Repository", snapshot.workspace.repository or "-" },
    { "Sticky Tag", snapshot.workspace.sticky_tag or "-" },
    { "Generated At", snapshot.generated_at or "-" },
  })

  render.section(lines, "Files")

  if #snapshot.files == 0 then
    lines[#lines + 1] = "No file state changes were parsed."
  else
    for _, file in ipairs(snapshot.files) do
      lines[#lines + 1] = ("%s  %s"):format(file.code, file.path)
    end
  end

  if snapshot.result then
    render.section(lines, "Command")
    lines[#lines + 1] = table.concat(snapshot.result.cmd, " ")
    lines[#lines + 1] = ("exit code: %s"):format(snapshot.result.code)
  end

  if snapshot.messages and #snapshot.messages > 0 then
    render.section(lines, "Messages")
    vim.list_extend(lines, snapshot.messages)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "q closes this buffer"
  lines[#lines + 1] = "R refreshes the status snapshot"

  return lines
end

return M
