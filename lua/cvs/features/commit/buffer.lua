local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")

local M = {}

local function comment(text)
  return "# " .. text
end

local function trim_message_lines(lines)
  local first = 1
  local last = #lines

  while first <= #lines and vim.trim(lines[first]) == "" do
    first = first + 1
  end

  while last >= first and vim.trim(lines[last]) == "" do
    last = last - 1
  end

  if first > last then
    return {}
  end

  return vim.list_slice(lines, first, last)
end

local function extract_message_lines(lines)
  local message_lines = {}

  for _, line in ipairs(lines or {}) do
    if not vim.startswith(line, "#") then
      message_lines[#message_lines + 1] = line
    end
  end

  return trim_message_lines(message_lines)
end

local function render_lines(view_state)
  local lines = vim.deepcopy(view_state.message_lines or { "" })
  if #lines == 0 then
    lines = { "" }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = comment("Write the CVS commit message above.")
  lines[#lines + 1] = comment("Use :write or press <C-c><C-c> in normal mode to submit.")
  lines[#lines + 1] = comment(("Workspace: %s"):format(view_state.workspace.root_dir))
  lines[#lines + 1] = comment(("Scope: %s"):format(view_state.scope_label))
  lines[#lines + 1] = comment(("Status: %s"):format(view_state.phase))

  if view_state.files and #view_state.files > 0 then
    lines[#lines + 1] = comment(("Selected Files (%d):"):format(#view_state.files))
    for _, file in ipairs(view_state.files) do
      lines[#lines + 1] = comment("  " .. file)
    end
  end

  if view_state.started_at then
    lines[#lines + 1] = comment(("Started At: %s"):format(view_state.started_at))
  end

  if view_state.completed_at then
    lines[#lines + 1] = comment(("Completed At: %s"):format(view_state.completed_at))
  end

  if view_state.command then
    local command_text = table.concat(view_state.command, " "):gsub("\r", "\\r"):gsub("\n", "\\n")
    lines[#lines + 1] = comment(("Command: %s"):format(command_text))
  end

  if view_state.messages and #view_state.messages > 0 then
    lines[#lines + 1] = comment("Messages:")
    for _, message in ipairs(view_state.messages) do
      lines[#lines + 1] = comment("  " .. message)
    end
  end

  return lines
end

function M.close(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      local tabpage = vim.api.nvim_win_get_tabpage(winid)
      if #vim.api.nvim_tabpage_list_wins(tabpage) > 1 then
        vim.api.nvim_win_close(winid, true)
      elseif #vim.api.nvim_list_tabpages() > 1 then
        vim.api.nvim_set_current_win(winid)
        vim.cmd("tabclose!")
      end
    end
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.get_message(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local message_lines = extract_message_lines(lines)
  if #message_lines == 0 then
    return {}, nil
  end

  return message_lines, table.concat(message_lines, "\n")
end

function M.open(view_state, opts)
  opts = opts or {}

  local bufnr = ui_buffer.create({
    name = ("cvs://commit/%s"):format(view_state.workspace.root_dir),
    buftype = "acwrite",
    filetype = "cvscommit",
  })

  ui_buffer.set_lines(bufnr, render_lines(view_state))
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      require("cvs.features.commit.service").submit(bufnr)
    end,
  })

  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        M.close(bufnr)
      end,
      desc = "Close CVS commit",
    },
    {
      mode = "n",
      lhs = "<C-c><C-c>",
      rhs = function()
        require("cvs.features.commit.service").submit(bufnr)
      end,
      desc = "Submit CVS commit",
    },
  })

  state.attach_buffer(bufnr, {
    kind = "commit",
    root_dir = view_state.workspace.root_dir,
    view_state = view_state,
  })

  local winid = window.open(bufnr, {
    kind = opts.kind or require("cvs.config").get().ui.commit.kind,
  })

  vim.api.nvim_win_set_cursor(winid, { 1, 0 })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      state.detach_buffer(bufnr)
    end,
  })

  return bufnr, winid
end

function M.update(bufnr, view_state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local attachment = state.get_buffer(bufnr) or {}
  attachment.kind = "commit"
  attachment.root_dir = view_state.workspace.root_dir
  attachment.view_state = view_state
  state.attach_buffer(bufnr, attachment)

  ui_buffer.set_lines(bufnr, render_lines(view_state))
end

M._extract_message_lines = extract_message_lines
M._render_lines = render_lines

return M
