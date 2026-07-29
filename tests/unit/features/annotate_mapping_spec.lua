local mapping = require("cvs.features.annotate.mapping")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function baseline(lines)
  local result = {}
  for index, text in ipairs(lines) do
    result[index] = {
      author = ("user%d"):format(index),
      text = text,
    }
  end
  return result
end

return function()
  local entries = baseline({ "one", "two", "three" })

  local empty, empty_stale = mapping.entries({}, { "" })
  assert_eq(#empty, 0, "empty file has no synthetic annotation")
  assert_eq(empty_stale, false, "empty file is unchanged")

  local first_local, first_local_stale = mapping.entries({}, { "first local line" })
  assert_eq(first_local[1].local_change, true, "first line in an empty baseline is local")
  assert_eq(first_local_stale, true, "edited empty baseline is stale")

  local inserted, inserted_stale = mapping.entries(entries, { "one", "local", "two", "three" })
  assert_eq(inserted_stale, true, "insertion marks annotations stale")
  assert_eq(inserted[2].local_change, true, "inserted line is local")
  assert_eq(inserted[3].author, "user2", "line after insertion keeps attribution")

  local replaced = mapping.entries(entries, { "one", "changed", "three" })
  assert_eq(replaced[2].local_change, true, "replacement is local")
  assert_eq(replaced[3].author, "user3", "line after replacement keeps attribution")

  local deleted = mapping.entries(entries, { "one", "three" })
  assert_eq(#deleted, 2, "deleted baseline line has no annotation row")
  assert_eq(deleted[2].author, "user3", "line after deletion keeps attribution")

  local cleared, cleared_stale = mapping.entries(entries, { "" })
  assert_eq(#cleared, 0, "cleared file has no annotation rows")
  assert_eq(cleared_stale, true, "cleared file remains stale")

  local unchanged, unchanged_stale = mapping.entries(entries, { "one", "two", "three" })
  assert_eq(unchanged_stale, false, "matching content is not stale")
  assert_eq(unchanged, entries, "matching content reuses baseline annotations")
end
