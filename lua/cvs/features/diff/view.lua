local config = require("cvs.config")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

local function close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function content(view_state)
  if view_state.loading then
    return { "Loading CVS diff..." }
  end

  if view_state.error then
    return { "CVS diff failed: " .. view_state.error }
  end

  local parsed = view_state.parsed or {}
  local lines = {}

  if view_state.source_modified then
    lines[#lines + 1] = "Unsaved buffer changes are not included in this CVS diff."
    lines[#lines + 1] = ""
  end

  vim.list_extend(lines, parsed.lines or {})

  if not parsed.truncated and (#lines == 0 or (#parsed.lines == 0 and view_state.source_modified and #lines == 2)) then
    if parsed.binary then
      lines[#lines + 1] = parsed.messages[1] or "Binary files differ."
    elseif #(parsed.messages or {}) > 0 then
      vim.list_extend(lines, parsed.messages)
    else
      lines[#lines + 1] = "No changes."
    end
  end

  if parsed.truncated then
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Diff truncated after reaching the configured %s limit."):format(
      parsed.truncation_reason or "output"
    )
  end

  return lines
end

local function set_content(bufnr, view_state)
  ui_buffer.set_lines(bufnr, content(view_state))
  ui_buffer.lock(bufnr)
end

local function jump_hunk(direction)
  local flags = direction > 0 and "W" or "bW"
  vim.fn.search("^@@", flags)
end

local function attach(bufnr, view_state, old)
  old = old or {}
  state.attach_buffer(bufnr, {
    kind = "diff",
    target_path = view_state.target_path,
    revision = view_state.revision,
    opts = old.opts or view_state.opts or {},
    process = old.process,
  })
end

function M.open(view_state, opts)
  opts = opts or {}

  local bufnr = ui_buffer.create({
    filetype = "diff",
  })
  vim.api.nvim_buf_set_name(
    bufnr,
    ("cvs://diff/%s@%s#%d"):format(view_state.target_path, view_state.revision, bufnr)
  )
  vim.bo[bufnr].undolevels = -1
  set_content(bufnr, view_state)

  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        close_buffer(bufnr)
      end,
      desc = "Close CVS diff",
    },
    {
      mode = "n",
      lhs = "]c",
      rhs = function()
        jump_hunk(1)
      end,
      desc = "Go to next CVS diff hunk",
    },
    {
      mode = "n",
      lhs = "[c",
      rhs = function()
        jump_hunk(-1)
      end,
      desc = "Go to previous CVS diff hunk",
    },
  })

  local winid = window.open(bufnr, {
    kind = opts.kind or config.get().ui.diff.kind,
  })

  attach(bufnr, view_state)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      require("cvs.features.diff.service").cancel(bufnr)
      state.detach_buffer(bufnr)
    end,
  })

  return bufnr, winid
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  set_content(bufnr, view_state)
  attach(bufnr, view_state, state.get_buffer(bufnr))
  return bufnr
end

function M.set_process(bufnr, process)
  local attachment = state.get_buffer(bufnr)
  if attachment then
    attachment.process = process
  end
end

return M
