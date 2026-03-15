local parse = require("cvs.features.annotate.parse")

local function read_lines(path)
  return vim.fn.readfile(path)
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function(root)
  local parsed = parse.parse(read_lines(root .. "/tests/fixtures/cvs/annotate/sample-basic.txt"))

  assert_eq(#parsed.entries, 4, "annotate entry count")
  assert_eq(parsed.entries[1].revision, "1.1", "first revision")
  assert_eq(parsed.entries[1].author, "mary", "first author")
  assert_eq(parsed.entries[1].date, "27-Mar-96", "first date")
  assert_eq(parsed.entries[2].date, "28-Mar-96 14:32", "second date with time")
  assert_eq(parsed.entries[3].text, "  return \"hi\"", "line text preserved")
  assert_eq(#parsed.messages, 0, "ignored annotate headers")
end
