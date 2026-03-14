local actions = require("cvs.features.status.actions")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

function M.open(snapshot, opts)
  opts = opts or {}

  local bufnr = ui_buffer.create({
    name = ("cvs://status/%s"):format(snapshot.workspace.root_dir),
    filetype = "cvs-status",
  })

  ui_buffer.set_lines(bufnr, require("cvs.features.status.render").lines(snapshot))
  ui_buffer.lock(bufnr)
  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        actions.close(bufnr)
      end,
      desc = "Close CVS status",
    },
    {
      mode = "n",
      lhs = "R",
      rhs = function()
        actions.refresh(snapshot.workspace.path)
      end,
      desc = "Refresh CVS status",
    },
  })

  state.attach_buffer(bufnr, {
    kind = "status",
    root_dir = snapshot.workspace.root_dir,
  })

  return bufnr, window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.status.kind,
  })
end

return M
