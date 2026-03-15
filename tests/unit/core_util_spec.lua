local util = require("cvs.core.util")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local original_cwd = vim.uv.cwd
  local original_buf_get_name = vim.api.nvim_buf_get_name

  vim.uv.cwd = function()
    return "/tmp/workspace"
  end

  vim.api.nvim_buf_get_name = function()
    return "@pkg/service/current.js"
  end

  local ok, err = pcall(function()
    assert_eq(util.resolve_path("@pkg/service/file.js"), "/tmp/workspace/pkg/service/file.js", "explicit alias path resolves from cwd")
    assert_eq(util.resolve_path(nil), "/tmp/workspace/pkg/service/current.js", "buffer alias path resolves from cwd")
  end)

  vim.uv.cwd = original_cwd
  vim.api.nvim_buf_get_name = original_buf_get_name

  if not ok then
    error(err)
  end
end
