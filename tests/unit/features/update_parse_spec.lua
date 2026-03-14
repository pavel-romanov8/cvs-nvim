local parse = require("cvs.features.update.parse")

local function read_lines(path)
  return vim.fn.readfile(path)
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function(root)
  local success = parse.parse(read_lines(root .. "/tests/fixtures/cvs/update/sample-success.txt"))
  assert_eq(#success.items, 4, "success item count")
  assert_eq(success.summary.updated, 1, "updated count")
  assert_eq(success.summary.patched, 1, "patched count")
  assert_eq(success.summary.modified, 1, "modified count")
  assert_eq(success.summary.unknown, 1, "unknown count")
  assert_eq(#success.messages, 0, "ignored update directory messages")

  local conflict = parse.parse(read_lines(root .. "/tests/fixtures/cvs/update/sample-conflict.txt"))
  assert_eq(#conflict.items, 3, "conflict item count")
  assert_eq(conflict.summary.updated, 1, "conflict updated count")
  assert_eq(conflict.summary.modified, 1, "conflict modified count")
  assert_eq(conflict.summary.conflict, 1, "conflict count")
  assert_eq(conflict.has_conflicts, true, "has conflicts flag")
  assert_eq(#conflict.messages, 1, "conflict warning message count")
end
