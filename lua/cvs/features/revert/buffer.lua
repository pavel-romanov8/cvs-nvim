local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}
local namespace = vim.api.nvim_create_namespace("cvs-revert")

function M.current(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "revert" then
    return nil
  end
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end
  return attachment.row_map and attachment.row_map[vim.api.nvim_win_get_cursor(winid)[1]] or nil
end

local function render(bufnr, view_state)
  local lines, row_map = require("cvs.features.revert.render").lines(view_state)
  ui_buffer.set_lines(bufnr, lines)
  ui_buffer.lock(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsHeader", 0, 0, -1)
  for row, line in ipairs(lines) do
    if line == "Affected files" or line:match("^Affected files:") or line:match("^Applied locally:") or line == "Blocked" then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsSection", row - 1, 0, -1)
    elseif line:match("^Cannot prepare revert:") or line:match("^    .*conflict") then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "ErrorMsg", row - 1, 0, -1)
    end
  end
  local attachment = state.get_buffer(bufnr)
  if attachment then
    attachment.view_state = view_state
    attachment.row_map = row_map
  end
end

function M.open(view_state, opts)
  local bufnr = ui_buffer.create({
    name = ("cvs://revert/%s"):format(view_state.commit_id),
    filetype = "cvs-revert",
  })
  state.attach_buffer(bufnr, { kind = "revert", view_state = view_state, row_map = {} })
  render(bufnr, view_state)
  ui_buffer.set_keymaps(bufnr, {
    { mode = "n", lhs = "q", rhs = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end, desc = "Close CVS revert plan" },
    { mode = "n", lhs = "yc", rhs = function()
      require("cvs.features.revert.service").copy_commit_id(bufnr)
    end, desc = "Copy CVS commit ID" },
    { mode = "n", lhs = "d", rhs = function()
      require("cvs.features.revert.service").preview(bufnr)
    end, desc = "Preview reverse diff for affected file" },
    { mode = "n", lhs = "dd", rhs = function()
      require("cvs.features.revert.service").preview(bufnr)
    end, desc = "Preview reverse diff for affected file" },
    { mode = "n", lhs = "R", rhs = function()
      require("cvs.features.revert.service").apply(bufnr, false)
    end, desc = "Apply CVS revert locally" },
    { mode = "n", lhs = "cc", rhs = function()
      require("cvs.features.revert.service").commit(bufnr)
    end, desc = "Apply and commit CVS revert" },
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      local attachment = state.get_buffer(bufnr)
      if attachment and attachment.process then
        require("cvs.cvs.runner").cancel(attachment.process)
      end
      state.detach_buffer(bufnr)
    end,
  })
  local cfg = require("cvs.config").get().ui.log
  return bufnr, window.open(bufnr, {
    kind = (opts and opts.kind) or cfg.kind,
    position = opts and opts.position,
    height = cfg.height,
    width = cfg.width,
  })
end

function M.update(bufnr, view_state)
  if vim.api.nvim_buf_is_valid(bufnr) then
    render(bufnr, view_state)
  end
end

return M
