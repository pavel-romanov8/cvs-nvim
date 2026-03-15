local service = require("cvs.features.files.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local original_buf_get_name = vim.api.nvim_buf_get_name

  vim.api.nvim_buf_get_name = function()
    return ""
  end

  local ok, err = pcall(function()
    local resolved, resolve_err = service._resolve_target_path({})
    assert_eq(resolved, nil, "missing add path returns nil")
    assert_eq(resolve_err.kind, "path_missing", "missing add path returns path_missing error")

    local label = service._scope_label({ root_dir = "/tmp/work" }, "/tmp/work/pkg/file.lua")
    assert_eq(label, "pkg/file.lua", "scope label is relative to workspace")
  end)

  vim.api.nvim_buf_get_name = original_buf_get_name

  if not ok then
    error(err)
  end
end
