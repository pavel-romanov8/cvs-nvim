local M = {}

function M.scan(root_dir)
  return vim.fs.find(function(name)
    return vim.startswith(name, ".#")
  end, {
    path = root_dir,
    limit = math.huge,
    type = "file",
  })
end

return M
