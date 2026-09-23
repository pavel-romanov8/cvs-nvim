local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}
local namespace = vim.api.nvim_create_namespace("cvs-log")

local function render(bufnr, view_state)
  local lines, row_map = require("cvs.features.log.render").lines(view_state)
  ui_buffer.set_lines(bufnr, lines)
  ui_buffer.lock(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsHeader", 0, 0, -1)
  for row, line in ipairs(lines) do
    if line:match("^revision [%d.]+") then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsSection", row - 1, 0, -1)
    end
  end
  local attachment = state.get_buffer(bufnr)
  if attachment then
    attachment.view_state = view_state
    attachment.row_map = row_map
  end
end

function M.current(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "log" then
    return nil
  end
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  return attachment.row_map[row]
end

function M.open(view_state, opts)
  local bufnr = ui_buffer.create({
    name = ("cvs://log/%s"):format(view_state.target_path),
    filetype = "cvs-log",
  })
  state.attach_buffer(bufnr, { kind = "log", view_state = view_state, row_map = {} })
  render(bufnr, view_state)
  ui_buffer.set_keymaps(bufnr, {
    { mode = "n", lhs = "q", rhs = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end, desc = "Close CVS history" },
    { mode = "n", lhs = "R", rhs = function()
      require("cvs.features.log.service").refresh(bufnr)
    end, desc = "Refresh CVS history" },
    { mode = "n", lhs = "<CR>", rhs = function()
      require("cvs.features.log.service").open_revision(bufnr)
    end, desc = "Open CVS revision" },
    { mode = "n", lhs = "=", rhs = function()
      require("cvs.features.log.service").toggle_preview(bufnr)
    end, desc = "Toggle inline CVS revision contents" },
    { mode = "n", lhs = "d", rhs = function()
      require("cvs.features.log.service").diff_revision(bufnr)
    end, desc = "Diff CVS revision with its predecessor" },
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      local attachment = state.get_buffer(bufnr)
      if attachment then
        if attachment.process then
          require("cvs.cvs.runner").cancel(attachment.process)
        end
        if attachment.preview_process then
          require("cvs.cvs.runner").cancel(attachment.preview_process)
        end
      end
      state.detach_buffer(bufnr)
    end,
  })
  return bufnr, window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.log.kind,
    position = opts.position,
  })
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local attachment = state.get_buffer(bufnr)
  local current = M.current(bufnr)
  if current then
    attachment.cursor_revision = current.revision
  end
  render(bufnr, view_state)
  if not view_state.loading and attachment.cursor_revision then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if line:match("^revision " .. vim.pesc(attachment.cursor_revision) .. "%s") then
          vim.api.nvim_win_set_cursor(winid, { row, 0 })
          break
        end
      end
    end
  end
end

return M
