local buffer = require("cvs.features.session.buffer")
local render = require("cvs.features.session.render")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local lines = {
    "Subject line",
    "",
    "Body line",
    "# Write the CVS commit message above.",
    "# [x] M lua/cvs/init.lua",
    "# [-] ? notes.txt -- press a to add this file",
  }

  local message_lines = buffer._extract_message_lines(lines)
  assert_eq(#message_lines, 3, "message line count")
  assert_eq(message_lines[1], "Subject line", "subject is preserved")
  assert_eq(message_lines[2], "", "blank body separator is preserved")
  assert_eq(message_lines[3], "Body line", "body is preserved")

  local rendered = render.lines({
    message_lines = { "Subject", "", "NOTIFY: nickname" },
    workspace = { root_dir = "/tmp/work" },
    scope_label = "workspace",
    phase = "running",
    selected_count = 1,
    selectable_count = 1,
    command = { "cvs", "commit", "-m", "Subject\n\nNOTIFY: nickname", "pkg/one.lua" },
  })
  for _, line in ipairs(rendered) do
    assert_eq(line:find("\n", 1, true), nil, "rendered command stays on one buffer line")
  end
  assert_eq(
    table.concat(rendered, "\n"):find("Subject\\n\\nNOTIFY: nickname", 1, true) ~= nil,
    true,
    "rendered command escapes message newlines"
  )
end
