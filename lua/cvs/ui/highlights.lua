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
  CvsStatusRemoved = "Typedef",
  CvsStatusUnknown = "StorageClass",
  CvsStatusConflict = "Structure",
  CvsStatusUpdated = "Structure",
  CvsStatusPatched = "Structure",
}

local function apply()
  for name, target in pairs(links) do
    local current = vim.api.nvim_get_hl(0, { name = name, link = true })
    if next(current) == nil then
      vim.api.nvim_set_hl(0, name, { link = target })
    end
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
