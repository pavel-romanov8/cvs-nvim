local service = require("cvs.features.annotate.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local request = service._build_request("/tmp/work/module/src/file.lua")

  assert_eq(request.cwd, "/tmp/work/module/src", "annotate cwd uses file directory")
  assert_eq(request.path, "file.lua", "annotate path uses basename")
end
