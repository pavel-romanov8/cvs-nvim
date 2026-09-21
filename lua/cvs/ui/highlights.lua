local M = {}

local initialized = false

local links = {
  CvsHeader = "Title",
  CvsSection = "PreProc",
  CvsLabel = "Identifier",
  CvsMuted = "Comment",
  CvsPath = "Directory",
  CvsStatusModified = "Structure",
  CvsStatusAdded = "Typedef",
  CvsStatusMissing = "WarningMsg",
  CvsStatusRemoved = "Typedef",
  CvsStatusUnknown = "StorageClass",
  CvsStatusConflict = "Structure",
  CvsStatusUpdated = "Structure",
  CvsStatusPatched = "Structure",
}

local diff_backgrounds = {
  CvsDiffAdd = "DiffAdd",
  CvsDiffChange = "DiffChange",
  CvsDiffDelete = "DiffDelete",
  CvsDiffText = "DiffText",
}

local function apply_diff_background(name, source_name)
  local source = vim.api.nvim_get_hl(0, { name = source_name, link = false })
  local background = source.bg
  local cterm_background = source.ctermbg
  if source.reverse then
    background = source.fg
    cterm_background = source.ctermfg
  end

  if background or cterm_background then
    vim.api.nvim_set_hl(0, name, {
      bg = background,
      ctermbg = cterm_background,
    })
  else
    vim.api.nvim_set_hl(0, name, { link = source_name })
  end
end

local function apply()
  for name, target in pairs(links) do
    local current = vim.api.nvim_get_hl(0, { name = name, link = true })
    if next(current) == nil then
      vim.api.nvim_set_hl(0, name, { link = target })
    end
  end

  for name, source in pairs(diff_backgrounds) do
    apply_diff_background(name, source)
  end
end

function M.setup()
  if initialized then
    return
  end

  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("CvsHighlights", { clear = true }),
    callback = apply,
  })

  initialized = true
end

return M
