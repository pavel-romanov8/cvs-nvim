local parse = require("cvs.features.diff.parse")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  local parser = parse.new()
  parser:feed("Index: file.lua\n================\nRCS file: /repo/file.lua,v\nretrieving revision 1.7\ndiff -u -r1.7 file.lua\n")
  parser:feed("--- file.lua\t2026-01-01\n+++ file.lua\t2026-01-02\n@@ -1,2 +1,2 @@\n-old")
  parser:feed("\n+new\n same\n\\ No newline at end of file\n")
  parser:feed("@@ -20 +20,2 @@ section\n context\n+added\n")

  local result = parser:finish()
  assert_eq(#result.hunks, 2, "stream parser finds both hunks")
  assert_eq(result.hunks[1].row, 1, "first hunk starts at the first retained line")
  assert_eq(result.hunks[2].row, 6, "second hunk records its retained row")
  assert_eq(result.lines[1], "@@ -1,2 +1,2 @@", "CVS preamble is removed")
  assert_eq(result.lines[2], "-old", "deleted line is retained")
  assert_eq(result.lines[3], "+new", "added line is retained")
  assert_eq(result.lines[5], "\\ No newline at end of file", "newline marker is retained")
  assert_eq(#result.messages, 0, "known CVS headers are not rendered as messages")

  local crlf = parse.new()
  crlf:feed("--- file.lua\r\n+++ file.lua\r\n@@ -1 +1 @@\r\n-old\r\n+new\r\n")
  local crlf_result = crlf:finish()
  assert_eq(crlf_result.lines[1], "@@ -1 +1 @@", "stream parser normalizes CRLF headers")
  assert_eq(crlf_result.lines[3], "+new", "stream parser normalizes CRLF body lines")

  local binary = parse.lines({ "Index: image.png", "Files image.png and /tmp/image.png differ" })
  assert_true(binary.binary, "binary output is recognized")
  assert_eq(binary.messages[1], "Files image.png and /tmp/image.png differ", "binary message is retained")

  local limited = parse.new({ max_lines = 2 })
  limited:feed("@@ -1,2 +1,2 @@\n-old\n+new\n same\n")
  local limited_result = limited:finish()
  assert_true(limited_result.truncated, "line limit truncates streamed output")
  assert_eq(limited_result.truncation_reason, "lines", "line truncation reports its reason")
  assert_eq(#limited_result.lines, 2, "line limit bounds retained output")

  local byte_limited = parse.new({ max_bytes = 20 })
  byte_limited:feed("@@ -1 +1 @@\n-old\n+new\n")
  local byte_result = byte_limited:finish()
  assert_true(byte_result.truncated, "byte limit truncates streamed output")
  assert_eq(byte_result.truncation_reason, "bytes", "byte truncation reports its reason")
  assert_true(byte_result.byte_count <= 20, "byte limit bounds consumed output")

  local malformed = parse.new()
  malformed:feed("@@ -1,2 +1,2 @@\n-old\n+new\n")
  assert_true(malformed:finish().error ~= nil, "incomplete hunks report a parse error")
end
