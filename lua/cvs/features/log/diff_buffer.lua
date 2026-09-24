local runner = require("cvs.cvs.runner")
local ui_buffer = require("cvs.ui.buffer")
local window = require("cvs.ui.window")
local source_syntax = require("cvs.features.diff.source_syntax")

local M = {}
local processes = {}
local namespace = vim.api.nvim_create_namespace("cvs-log-full-syntax")

local function lines(view)
  local title = ("CVS diff: %s  %s -> %s"):format(
    view.path, view.from or "(empty)", view.to
  )
  if view.loading then
    return { title, "", "Loading revision diff..." }
  end
  if view.error then
    return { title, "", "Could not load diff: " .. view.error }
  end
  local parsed = view.parsed
  local result = { title, "" }
  vim.list_extend(result, parsed.lines)
  if #parsed.lines == 0 and #parsed.messages == 0 then
    result[#result + 1] = "No differences."
  end
  vim.list_extend(result, parsed.messages)
  if parsed.truncated then
    result[#result + 1] = "... (diff truncated; adjust diff.max_bytes / diff.max_lines)"
  end
  return result
end

function M.update(bufnr, view)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  ui_buffer.set_lines(bufnr, lines(view))
  ui_buffer.lock(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  if not view.parsed then return end
  require("cvs.ui.highlights").setup()
  for row, line in ipairs(view.parsed.lines) do
    local group
    if line:match("^@@") then group = "CvsDiffChange"
    elseif line:match("^%+") then group = "CvsDiffAdd"
    elseif line:match("^%-") then group = "CvsDiffDelete" end
    if group then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row + 1, 0, {
        end_col = #line, hl_group = group, priority = 100,
      })
    end
  end
  if require("cvs.config").get().diff.syntax_highlighting ~= false then
    local parsed = view.parsed
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) or view.parsed ~= parsed then return end
      local tokens = source_syntax.captures(parsed.lines, view.path)
      source_syntax.apply(bufnr, namespace, tokens, function(row) return row + 2 end, 1)
    end)
  end
end

function M.open(view)
  local bufnr = ui_buffer.create({
    name = ("cvs://revision-diff/%s/%s..%s"):format(view.path, view.from or "empty", view.to),
    filetype = "diff",
  })
  -- This view is a unified diff, even when the user's config has syntax off.
  vim.bo[bufnr].syntax = "diff"
  M.update(bufnr, view)
  ui_buffer.set_keymaps(bufnr, {
    { mode = "n", lhs = "q", rhs = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end, desc = "Close CVS revision diff" },
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      if processes[bufnr] then
        runner.cancel(processes[bufnr])
        processes[bufnr] = nil
      end
    end,
  })
  local winid = window.open(bufnr, { kind = "split" })
  return bufnr, winid
end

function M.set_process(bufnr, process)
  processes[bufnr] = process
end

function M.clear_process(bufnr)
  processes[bufnr] = nil
end

return M
