local config = require("cvs.config")
local state = require("cvs.core.state")
local ui_buffer = require("cvs.ui.buffer")

local M = {}

local function source_filetype(view_state)
  local bufnr = view_state.source_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return vim.bo[bufnr].filetype
  end
  return vim.filetype.match({ filename = view_state.target_path }) or ""
end

local function shared_lines(view_state)
  if view_state.loading then
    return { "Loading CVS diff..." }
  end
  if view_state.error then
    return { "CVS diff failed: " .. view_state.error }
  end

  local parsed = view_state.parsed or {}
  if parsed.binary then
    return { parsed.messages[1] or "Binary files differ." }
  end
  if #(parsed.messages or {}) > 0 then
    return vim.deepcopy(parsed.messages)
  end
  if not parsed.truncated then
    return { "No changes." }
  end
  return {}
end

local function build_content(view_state)
  local parsed = view_state.parsed or {}
  local sides = require("cvs.features.diff.sides").build(parsed)

  if #sides.old_lines == 0 and #sides.new_lines == 0 then
    local lines = shared_lines(view_state)
    sides.old_lines = vim.deepcopy(lines)
    sides.new_lines = vim.deepcopy(lines)
  end

  if view_state.source_modified and not view_state.loading then
    table.insert(sides.old_lines, 1, "Unsaved buffer changes are not included in this CVS diff.")
    table.insert(sides.new_lines, 1, "Unsaved buffer changes are not included in this CVS diff.")
    table.insert(sides.old_lines, 2, "")
    table.insert(sides.new_lines, 2, "")
  end

  if parsed.truncated then
    local message = ("Diff truncated after reaching the configured %s limit."):format(
      parsed.truncation_reason or "output"
    )
    sides.old_lines[#sides.old_lines + 1] = ""
    sides.new_lines[#sides.new_lines + 1] = ""
    sides.old_lines[#sides.old_lines + 1] = message
    sides.new_lines[#sides.new_lines + 1] = message
  end

  return sides
end

local function set_content(pair, view_state)
  local content = build_content(view_state)
  ui_buffer.set_lines(pair.old_bufnr, content.old_lines)
  ui_buffer.set_lines(pair.new_bufnr, content.new_lines)
  ui_buffer.lock(pair.old_bufnr)
  ui_buffer.lock(pair.new_bufnr)
end

local function set_diff(winid, enabled)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  vim.api.nvim_win_call(winid, function()
    vim.cmd(enabled and "diffthis" or "silent! diffoff")
  end)
end

local function enable_pair(pair)
  if pair.diff_enabled then
    return
  end

  set_diff(pair.old_win, true)
  set_diff(pair.new_win, true)
  pair.diff_enabled = true
end

local function attach(pair, process)
  state.attach_buffer(pair.old_bufnr, {
    kind = "diff",
    side = "base",
    pair = pair,
    process = process,
  })
  state.attach_buffer(pair.new_bufnr, {
    kind = "diff",
    side = "working",
    pair = pair,
    process = process,
  })
end

local function delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.close(bufnr, wiping)
  local attachment = state.get_buffer(bufnr)
  local pair = attachment and attachment.pair
  if not pair or pair.closing then
    return
  end
  pair.closing = true

  require("cvs.features.diff.service").cancel(pair.old_bufnr)
  set_diff(pair.old_win, false)
  set_diff(pair.new_win, false)

  if pair.restore_source then
    local restore_win = vim.api.nvim_win_is_valid(pair.old_win) and pair.old_win
      or (vim.api.nvim_win_is_valid(pair.new_win) and pair.new_win or nil)
    for _, winid in ipairs({ pair.old_win, pair.new_win }) do
      if winid ~= restore_win and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end
    if restore_win and vim.api.nvim_buf_is_valid(pair.source_bufnr) then
      vim.api.nvim_win_set_buf(restore_win, pair.source_bufnr)
      vim.wo[restore_win].winbar = pair.old_winbar
      vim.api.nvim_set_current_win(restore_win)
    end
  elseif not wiping
    and pair.tabpage
    and vim.api.nvim_tabpage_is_valid(pair.tabpage)
    and #vim.api.nvim_list_tabpages() > 1
  then
    vim.api.nvim_set_current_tabpage(pair.tabpage)
    vim.cmd("tabclose")
  end

  state.detach_buffer(pair.old_bufnr)
  state.detach_buffer(pair.new_bufnr)
  if pair.old_bufnr ~= wiping then
    delete_buffer(pair.old_bufnr)
  end
  if pair.new_bufnr ~= wiping then
    delete_buffer(pair.new_bufnr)
  end
end

local function set_keymaps(bufnr)
  ui_buffer.set_keymaps(bufnr, {
    {
      mode = "n",
      lhs = "q",
      rhs = function()
        M.close(bufnr)
      end,
      desc = "Close CVS diff",
    },
  })
end

local function create_buffer(view_state, side)
  local bufnr = ui_buffer.create({
    filetype = source_filetype(view_state),
  })
  vim.api.nvim_buf_set_name(
    bufnr,
    ("cvs://diff/%s/%s@%s#%d"):format(side, view_state.target_path, view_state.revision, bufnr)
  )
  vim.bo[bufnr].undolevels = -1
  return bufnr
end

local function tab_has_diff_window(winid)
  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.wo[candidate].diff then
      return true
    end
  end
  return false
end

function M.open(view_state, opts)
  opts = opts or {}

  local old_bufnr = create_buffer(view_state, "base")
  local new_bufnr = create_buffer(view_state, "working")
  local kind = opts.kind or config.get().ui.diff.kind
  if kind ~= "vsplit" and kind ~= "tab" then
    kind = "tab"
  end
  local source_win = view_state.source_win
  local source_bufnr = view_state.source_bufnr
  local restore_source = kind == "vsplit"
    and source_win
    and vim.api.nvim_win_is_valid(source_win)
    and source_bufnr
    and vim.api.nvim_buf_is_valid(source_bufnr)
    and vim.api.nvim_win_get_buf(source_win) == source_bufnr
    and not tab_has_diff_window(source_win)

  local old_win
  local old_winbar = ""
  local tabpage
  if restore_source then
    old_win = source_win
    old_winbar = vim.wo[old_win].winbar
    vim.api.nvim_win_set_buf(old_win, old_bufnr)
    vim.api.nvim_set_current_win(old_win)
  else
    vim.cmd("tabnew")
    tabpage = vim.api.nvim_get_current_tabpage()
    old_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(old_win, old_bufnr)
  end

  local new_win = vim.api.nvim_win_call(old_win, function()
    vim.cmd("rightbelow vsplit")
    return vim.api.nvim_get_current_win()
  end)
  vim.api.nvim_win_set_buf(new_win, new_bufnr)
  vim.wo[old_win].winbar = "CVS BASE"
  vim.wo[new_win].winbar = "CVS WORKING"

  local pair = {
    old_bufnr = old_bufnr,
    new_bufnr = new_bufnr,
    old_win = old_win,
    new_win = new_win,
    source_bufnr = source_bufnr,
    restore_source = restore_source,
    old_winbar = old_winbar,
    tabpage = tabpage,
  }

  set_content(pair, view_state)
  set_keymaps(old_bufnr)
  set_keymaps(new_bufnr)
  attach(pair)
  if not view_state.loading and not view_state.error then
    enable_pair(pair)
  end

  for _, bufnr in ipairs({ old_bufnr, new_bufnr }) do
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        if not pair.closing and not pair.cleanup_scheduled then
          require("cvs.features.diff.service").cancel(bufnr)
          pair.cleanup_scheduled = true
          vim.schedule(function()
            pair.cleanup_scheduled = false
            M.close(bufnr, bufnr)
          end)
        end
      end,
    })
  end

  return old_bufnr, new_bufnr, old_win, new_win
end

function M.update(bufnr, view_state)
  local attachment = state.get_buffer(bufnr)
  local pair = attachment and attachment.pair
  if not pair
    or pair.closing
    or pair.cleanup_scheduled
    or not vim.api.nvim_buf_is_valid(pair.old_bufnr)
    or not vim.api.nvim_buf_is_valid(pair.new_bufnr)
  then
    return nil
  end

  set_content(pair, view_state)
  if not view_state.loading and not view_state.error then
    enable_pair(pair)
  end
  return pair.old_bufnr, pair.new_bufnr
end

function M.set_process(bufnr, process)
  local attachment = state.get_buffer(bufnr)
  local pair = attachment and attachment.pair
  if pair then
    pair.process = process
    attach(pair, process)
  end
end

return M
