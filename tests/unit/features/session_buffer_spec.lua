local buffer = require("cvs.features.session.buffer")

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
end
