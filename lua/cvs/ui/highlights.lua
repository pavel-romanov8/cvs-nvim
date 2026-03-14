local M = {}

local initialized = false

function M.setup()
  if initialized then
    return
  end

  vim.api.nvim_set_hl(0, "CvsHeader", { link = "Title" })
  vim.api.nvim_set_hl(0, "CvsLabel", { link = "Identifier" })
  vim.api.nvim_set_hl(0, "CvsMuted", { link = "Comment" })
  vim.api.nvim_set_hl(0, "CvsPath", { link = "Directory" })

  initialized = true
end

return M
