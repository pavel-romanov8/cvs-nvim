local config = require("cvs.config")
local service = require("cvs.features.diff.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local temp_dir = vim.fn.tempname()
  local cvs_dir = temp_dir .. "/CVS"
  local target = temp_dir .. "/file.lua"
  local fake_cvs = temp_dir .. "/fake-cvs"

  vim.fn.mkdir(cvs_dir, "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, cvs_dir .. "/Root")
  vim.fn.writefile({ "module" }, cvs_dir .. "/Repository")
  vim.fn.writefile({ "/file.lua/1.7/Thu Jan 01 00:00:00 2026//" }, cvs_dir .. "/Entries")
  vim.fn.writefile({ "working content" }, target)
  vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")

  config.setup({
    cvs = {
      bin = fake_cvs,
    },
    notifications = {
      enabled = false,
    },
  })

  local view_state, err = service._prepare({ path = target })
  assert_eq(err, nil, "tracked file prepares without an error")
  assert_eq(view_state.target_path, target, "diff resolves the target path")
  assert_eq(view_state.revision, "1.7", "diff uses the checked-out revision")
  assert_eq(view_state.request.cwd, temp_dir, "CVS base command runs beside the file")
  assert_eq(
    table.concat(view_state.command, " "),
    fake_cvs .. " -Q update -p -r 1.7 file.lua",
    "diff prints the checked-out file revision"
  )

  vim.fn.writefile({ "/file.lua/0/Initial file//" }, cvs_dir .. "/Entries")
  local missing, missing_err = service._prepare({ path = target })
  assert_eq(missing, nil, "added file has no CVS base")
  assert_eq(missing_err.kind, "base_revision_missing", "missing base reports a specific error")

  config.setup()
  vim.fn.delete(temp_dir, "rf")
end
