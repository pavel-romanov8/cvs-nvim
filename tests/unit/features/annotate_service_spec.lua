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

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir .. "/CVS", "p")
  vim.fn.writefile({ "/file.lua/1.7/Thu Jan 01 00:00:00 2026//" }, temp_dir .. "/CVS/Entries")

  local revision_request = service._build_request(temp_dir .. "/file.lua")
  assert_eq(revision_request.revision, "1.7", "annotate uses the checked-out revision")
  assert_eq(service._valid_revision("1.7.2.1"), true, "branch revision is valid")
  assert_eq(service._valid_revision("1..7"), false, "malformed revision is ignored")
  assert_eq(service._valid_revision("0"), false, "added file revision is ignored")

  vim.fn.delete(temp_dir, "rf")
end
