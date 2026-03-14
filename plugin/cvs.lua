if vim.g.loaded_cvs_nvim == 1 then
  return
end

vim.g.loaded_cvs_nvim = 1

require("cvs").setup()
