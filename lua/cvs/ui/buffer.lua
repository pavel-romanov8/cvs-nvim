local M = {}

function M.create(opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_create_buf(false, true)
  local bo = vim.bo[bufnr]

  bo.bufhidden = opts.bufhidden or "wipe"
  bo.buftype = opts.buftype or "nofile"
  bo.swapfile = false
  bo.modifiable = true
  bo.readonly = false

  if opts.filetype then
    bo.filetype = opts.filetype
  end

  if opts.name then
    pcall(vim.api.nvim_buf_set_name, bufnr, opts.name)
  end

  return bufnr
end

function M.set_lines(bufnr, lines)
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function M.lock(bufnr)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
end

function M.set_keymaps(bufnr, keymaps)
  for _, keymap in ipairs(keymaps or {}) do
    vim.keymap.set(keymap.mode, keymap.lhs, keymap.rhs, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = keymap.desc,
    })
  end
end

return M
