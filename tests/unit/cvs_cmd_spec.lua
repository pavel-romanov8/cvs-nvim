local cmd = require("cvs.cvs.cmd")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  require("cvs.config").setup({
    cvs = {
      bin = "cvs",
      global_args = { "-f" },
    },
  })

  local add_cmd = cmd.add({ path = "pkg/file.lua" })
  assert_eq(table.concat(add_cmd, " "), "cvs -f add pkg/file.lua", "add command includes path")

  local commit_cmd = cmd.commit({
    message = "Fix it",
    files = { "pkg/file.lua", "pkg/other.lua" },
  })
  assert_eq(
    table.concat(commit_cmd, " "),
    "cvs -f commit -m Fix it pkg/file.lua pkg/other.lua",
    "commit command includes message and files"
  )
end
