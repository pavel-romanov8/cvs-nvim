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

  local bulk_add_cmd = cmd.add({ files = { "pkg/one.lua", "pkg/two.lua" } })
  assert_eq(
    table.concat(bulk_add_cmd, " "),
    "cvs -f add pkg/one.lua pkg/two.lua",
    "add command includes multiple files"
  )

  local binary_add_cmd = cmd.add({ files = { "assets/logo.png" }, binary = true })
  assert_eq(
    table.concat(binary_add_cmd, " "),
    "cvs -f add -kb assets/logo.png",
    "binary add sets the CVS binary keyword mode"
  )

  local commit_cmd = cmd.commit({
    message = "Fix it",
    files = { "pkg/file.lua", "pkg/other.lua" },
  })
  assert_eq(
    table.concat(commit_cmd, " "),
    "cvs -f commit -m Fix it pkg/file.lua pkg/other.lua",
    "commit command includes message and files"
  )

  local multiline_commit_cmd = cmd.commit({
    message = "Fix it\n\nNOTIFY: nickname",
    files = { "pkg/file.lua" },
  })
  assert_eq(
    multiline_commit_cmd[5],
    "Fix it\n\nNOTIFY: nickname",
    "commit command preserves a multiline message as one argument"
  )

  local remove_cmd = cmd.remove({ path = "pkg/file.lua" })
  assert_eq(table.concat(remove_cmd, " "), "cvs -f remove -f pkg/file.lua", "remove command includes force flag and path")

  local status_cmd = cmd.status({})
  assert_eq(table.concat(status_cmd, " "), "cvs -f -nq update", "status command is a read-only update")

  local update_cmd = cmd.update({})
  assert_eq(table.concat(update_cmd, " "), "cvs -f -q update -d", "update creates repository directories")

  local restore_cmd = cmd.restore({ files = { "pkg/file.lua" } })
  assert_eq(table.concat(restore_cmd, " "), "cvs -f -q update pkg/file.lua", "restore checks out missing files")

  local discard_cmd = cmd.discard({ files = { "pkg/file.lua" } })
  assert_eq(
    table.concat(discard_cmd, " "),
    "cvs -f -q update -C pkg/file.lua",
    "discard replaces local changes"
  )

  local annotate_cmd = cmd.annotate({ path = "pkg/file.lua", revision = "1.7" })
  assert_eq(table.concat(annotate_cmd, " "), "cvs -f annotate -r 1.7 pkg/file.lua", "annotate pins the revision")

  local base_cmd = cmd.base({ path = "file.lua", revision = "1.7" })
  assert_eq(
    table.concat(base_cmd, " "),
    "cvs -f -Q update -p -r 1.7 file.lua",
    "base command prints the checked-out revision"
  )
end
