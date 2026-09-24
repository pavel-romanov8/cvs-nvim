local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")
local source_syntax = require("cvs.features.diff.source_syntax")

local M = {}
local namespace = vim.api.nvim_create_namespace("cvs-log")

local function render(bufnr, view_state)
  local lines, row_map, highlights, syntax_rows = require("cvs.features.log.render").lines(view_state)
  ui_buffer.set_lines(bufnr, lines)
  ui_buffer.lock(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  require("cvs.ui.highlights").setup()
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsHeader", 0, 0, -1)
  for row, line in ipairs(lines) do
    if line:match("^revision [%d.]+") or line:match("^commit %S+") then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "CvsSection", row - 1, 0, -1)
    end
  end
  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace, highlight.row - 1, 6, {
      end_col = #lines[highlight.row], hl_group = highlight.group, priority = 100,
    })
  end
  local inline = view_state.inline
  if inline and inline.syntax then
    source_syntax.apply(bufnr, namespace, inline.syntax, syntax_rows, 7)
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
    name = ("cvs://log/%s"):format(view_state.target_path or view_state.scope_path),
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
    { mode = "n", lhs = "L", rhs = function()
      require("cvs.features.log.service").load_older(bufnr)
    end, desc = "Load an older CVS history range" },
    { mode = "n", lhs = "<CR>", rhs = function()
      require("cvs.features.log.service").open_revision(bufnr)
    end, desc = "Open CVS revision diff" },
    { mode = "n", lhs = "=", rhs = function()
      require("cvs.features.log.service").toggle_preview(bufnr)
    end, desc = "Toggle inline CVS revision diff" },
    { mode = "n", lhs = "d", rhs = function()
      require("cvs.features.log.service").diff_revision(bufnr)
    end, desc = "Diff CVS revision with its predecessor" },
    { mode = "n", lhs = "yc", rhs = function()
      require("cvs.features.log.service").copy_commit_id(bufnr)
    end, desc = "Copy CVS commit ID" },
    { mode = "n", lhs = "cr", rhs = function()
      require("cvs.features.log.service").revert_commit(bufnr)
    end, desc = "Revert complete CVS commit" },
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
  local log_config = require("cvs.config").get().ui.log
  return bufnr, window.open(bufnr, {
    kind = opts.kind or log_config.kind,
    position = opts.position,
    height = opts.height or log_config.height,
    width = opts.width or log_config.width,
  })
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local attachment = state.get_buffer(bufnr)
  local current = M.current(bufnr)
  if current then
    if current.kind == "commit" or current.kind == "change" then
      attachment.cursor_commit = current.commit.key
    else
      attachment.cursor_revision = current.revision
    end
  end
  render(bufnr, view_state)
  if not view_state.loading and (attachment.cursor_revision or attachment.cursor_commit) then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      local current_map = attachment.row_map or {}
      for row, target in pairs(current_map) do
        local matches_revision = attachment.cursor_revision and target.revision == attachment.cursor_revision
        local matches_commit = attachment.cursor_commit
          and (target.kind == "commit" or target.kind == "change")
          and target.commit.key == attachment.cursor_commit
        if matches_revision or matches_commit then
          vim.api.nvim_win_set_cursor(winid, { row, 0 })
          break
        end
      end
    end
  end
end

return M
