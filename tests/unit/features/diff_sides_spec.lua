local sides = require("cvs.features.diff.sides")

local function assert_eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local result = sides.build({
    lines = {
      "@@ -10,3 +10,4 @@ section",
      " context",
      "-old line",
      "+new line",
      "+another line",
      " tail",
      "@@ -30,2 +31 @@",
      "-removed one",
      "-removed two",
      "+replacement",
    },
    hunks = {
      { header = "@@ -10,3 +10,4 @@ section", row = 1 },
      { header = "@@ -30,2 +31 @@", row = 7 },
    },
  })

  assert_eq(result.old_lines, {
    "@@ -10,3 +10,4 @@ section",
    "context",
    "old line",
    "tail",
    "@@ -30,2 +31 @@",
    "removed one",
    "removed two",
  }, "old side contains context and deletions")
  assert_eq(result.new_lines, {
    "@@ -10,3 +10,4 @@ section",
    "context",
    "new line",
    "another line",
    "tail",
    "@@ -30,2 +31 @@",
    "replacement",
  }, "new side contains context and additions")
  local newline_result = sides.build({
    lines = {
      "@@ -1 +1 @@",
      "-old",
      "\\ No newline at end of file",
      "+new",
      "\\ No newline at end of file",
    },
    hunks = {
      { header = "@@ -1 +1 @@", row = 1 },
    },
  })
  assert_eq(newline_result.old_lines[3], "\\ No newline at end of file", "old newline marker stays on base")
  assert_eq(newline_result.new_lines[3], "\\ No newline at end of file", "new newline marker stays on working side")
end
