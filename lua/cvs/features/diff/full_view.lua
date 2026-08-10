local ui_buffer = require("cvs.ui.buffer")

local M = {}
local active = {}

local function source_window(view_state)
  local bufnr = view_state.source_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local winid = view_state.source_win
    if winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return bufnr, winid
    end

    for _, candidate in ipairs(vim.fn.win_findbuf(bufnr)) do
      if vim.api.nvim_win_is_valid(candidate) then
        return bufnr, candidate
      end
    end
  else
    bufnr = vim.fn.bufadd(view_state.target_path)
    vim.fn.bufload(bufnr)
  end

  vim.cmd(("tab sbuffer %d"):format(bufnr))
  return bufnr, vim.api.nvim_get_current_win()
end

local function enable_diff(winid)
  vim.api.nvim_win_call(winid, function()
    vim.cmd("diffthis")
  end)
end

function M.open(view_state)
  local source_bufnr, source_win = source_window(view_state)
  if not source_win then
    return nil
  end

  local previous = active[source_win]
  local owns_source_diff = not vim.wo[source_win].diff
  if previous then
    owns_source_diff = previous.owns_source_diff
    active[source_win] = nil
    if vim.api.nvim_win_is_valid(previous.base_win) then
      vim.api.nvim_win_close(previous.base_win, true)
    end
    if vim.api.nvim_buf_is_valid(previous.base_bufnr) then
      vim.api.nvim_buf_delete(previous.base_bufnr, { force = true })
    end
  end

  local base_bufnr = ui_buffer.create({
    filetype = vim.bo[source_bufnr].filetype,
  })
  vim.api.nvim_buf_set_name(
    base_bufnr,
    ("cvs://base/%s@%s#%d"):format(view_state.target_path, view_state.revision, base_bufnr)
  )
  vim.bo[base_bufnr].undolevels = -1
  ui_buffer.set_lines(base_bufnr, view_state.result.stdout)
  vim.bo[base_bufnr].endofline = view_state.result.stdout_ends_with_newline ~= false
  ui_buffer.lock(base_bufnr)

  local base_win = vim.api.nvim_win_call(source_win, function()
    vim.cmd("leftabove vsplit")
    return vim.api.nvim_get_current_win()
  end)
  vim.api.nvim_win_set_buf(base_win, base_bufnr)

  local ok, err = pcall(function()
    enable_diff(source_win)
    enable_diff(base_win)
  end)
  if not ok then
    if owns_source_diff and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_call(source_win, function()
        vim.cmd("silent! diffoff")
      end)
    end
    if vim.api.nvim_win_is_valid(base_win) then
      vim.api.nvim_win_close(base_win, true)
    end
    if vim.api.nvim_buf_is_valid(base_bufnr) then
      vim.api.nvim_buf_delete(base_bufnr, { force = true })
    end
    error(err)
  end

  active[source_win] = {
    base_bufnr = base_bufnr,
    base_win = base_win,
    owns_source_diff = owns_source_diff,
  }

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = base_bufnr,
    once = true,
    callback = function()
      local current = active[source_win]
      if not current or current.base_bufnr ~= base_bufnr then
        return
      end

      active[source_win] = nil
      if current.owns_source_diff
        and vim.api.nvim_win_is_valid(source_win)
        and vim.api.nvim_win_get_buf(source_win) == source_bufnr
      then
        vim.api.nvim_win_call(source_win, function()
          vim.cmd("diffoff")
        end)
      end
    end,
  })

  return base_bufnr, base_win, source_win
end

return M
