local config = require("cvs.config")

local M = {}

local diff_highlights = {
  { from = "DiffAdd", to = "CvsDiffAdd" },
  { from = "DiffChange", to = "CvsDiffChange" },
  { from = "DiffDelete", to = "CvsDiffDelete" },
  { from = "DiffText", to = "CvsDiffText" },
}

local function diff_config()
  return config.get().diff or {}
end

local function mapped_winhighlight(value)
  local replaced = {}
  for _, mapping in ipairs(diff_highlights) do
    replaced[mapping.from] = true
  end

  local items = {}
  for item in (value or ""):gmatch("[^,]+") do
    local source = item:match("^([^:]+):")
    if not replaced[source] then
      items[#items + 1] = item
    end
  end

  for _, mapping in ipairs(diff_highlights) do
    items[#items + 1] = mapping.from .. ":" .. mapping.to
  end
  return table.concat(items, ",")
end

function M.style_window(winid)
  if diff_config().preserve_syntax_colors == false
    or not winid
    or not vim.api.nvim_win_is_valid(winid)
  then
    return nil
  end

  require("cvs.ui.highlights").setup()
  local previous = vim.wo[winid].winhighlight
  local applied = mapped_winhighlight(previous)
  vim.wo[winid].winhighlight = applied
  return {
    previous = previous,
    applied = applied,
  }
end

function M.restore_window(winid, style)
  if style and winid and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].winhighlight = style.previous
  end
end

function M.enable_syntax(bufnr)
  if diff_config().syntax_highlighting == false
    or not bufnr
    or not vim.api.nvim_buf_is_valid(bufnr)
  then
    return false
  end

  local filetype = vim.bo[bufnr].filetype
  if filetype == "" then
    return false
  end

  if vim.treesitter and vim.treesitter.start then
    local ok = pcall(vim.treesitter.start, bufnr)
    if ok then
      return true
    end
  end

  -- Keep source highlighting available when no Tree-sitter parser is installed.
  if vim.bo[bufnr].syntax == "" then
    vim.bo[bufnr].syntax = filetype
  end
  return false
end

return M
