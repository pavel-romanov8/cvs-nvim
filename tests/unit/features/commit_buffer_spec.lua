local buffer = require("cvs.features.commit.buffer")

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
    "# Status: editing",
  }

  local message_lines = buffer._extract_message_lines(lines)
  assert_eq(#message_lines, 3, "message line count")
  assert_eq(message_lines[1], "Subject line", "subject is preserved")
  assert_eq(message_lines[2], "", "blank body separator is preserved")
  assert_eq(message_lines[3], "Body line", "body is preserved")

  local rendered = buffer._render_lines({
    message_lines = { "" },
    workspace = { root_dir = "/tmp/work" },
    scope_label = "2 selected files",
    phase = "editing",
    files = { "pkg/one.lua", "pkg/two.lua" },
  })
  local text = table.concat(rendered, "\n")
  assert_eq(text:find("# Selected Files (2):", 1, true) ~= nil, true, "selected file heading is rendered")
  assert_eq(text:find("#   pkg/one.lua", 1, true) ~= nil, true, "first selected file is rendered")
  assert_eq(text:find("#   pkg/two.lua", 1, true) ~= nil, true, "second selected file is rendered")

  rendered = buffer._render_lines({
    message_lines = { "Subject", "", "NOTIFY: nickname" },
    workspace = { root_dir = "/tmp/work" },
    scope_label = "pkg/one.lua",
    phase = "running",
    files = { "pkg/one.lua" },
    command = { "cvs", "commit", "-m", "Subject\n\nNOTIFY: nickname", "pkg/one.lua" },
  })
  for _, line in ipairs(rendered) do
    assert_eq(line:find("\n", 1, true), nil, "rendered command stays on one buffer line")
  end
  text = table.concat(rendered, "\n")
  assert_eq(
    text:find("Subject\\n\\nNOTIFY: nickname", 1, true) ~= nil,
    true,
    "rendered command escapes message newlines"
  )
end
