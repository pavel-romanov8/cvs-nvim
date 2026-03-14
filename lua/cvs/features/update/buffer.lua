local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

local function set_content(bufnr, view_state)
  ui_buffer.set_lines(bufnr, require("cvs.features.update.render").lines(view_state))
  ui_buffer.lock(bufnr)
end

function M.open(view_state, opts)
  local bufnr = ui_buffer.create({
    name = ("cvs://update/%s"):format(view_state.workspace.root_dir),
    filetype = "cvs-update",
  })

  set_content(bufnr, view_state)
  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end,
      desc = "Close CVS update",
    },
  })

  state.attach_buffer(bufnr, {
    kind = "update",
    root_dir = view_state.workspace.root_dir,
  })

  return bufnr, window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.update.kind,
  })
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  set_content(bufnr, view_state)
end

return M
