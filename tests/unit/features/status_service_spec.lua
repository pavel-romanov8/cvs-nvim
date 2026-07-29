local service = require("cvs.features.status.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function find_section(view_state, kind)
  for _, section in ipairs(view_state.sections or {}) do
    if section.kind == kind then
      return section
    end
  end

  return nil
end

return function()
  local snapshot = {
    workspace = {
      root_dir = "/tmp/example",
    },
    generated_at = "2026-03-27 12:00:00",
    files = {
      { code = "M", path = "lua/cvs/init.lua", status = "modified" },
      { code = "A", path = "lua/cvs/new.lua", status = "added" },
      { code = "R", path = "lua/cvs/old.lua", status = "removed" },
      { code = "?", path = "notes.txt", status = "unknown" },
      { code = "C", path = "plugin/cvs.lua", status = "conflict" },
      { code = "U", path = "README.md", status = "updated" },
    },
    messages = {
      "status warning",
    },
  }

  local view_state = service._build_view_state(snapshot, {}, {})
  assert_eq(view_state.scope_label, "workspace", "default scope label")
  assert_eq(view_state.total_count, 6, "file count")
  assert_eq(view_state.counts.modified, 1, "modified count")
  assert_eq(view_state.counts.unknown, 1, "unknown count")
  assert_eq(view_state.messages[1], "status warning", "messages are preserved")

  local modified = find_section(view_state, "modified")
  local unknown = find_section(view_state, "unknown")
  local updated = find_section(view_state, "updated")

  assert_eq(#modified.items, 1, "modified section item count")
  assert_eq(modified.items[1].path, "lua/cvs/init.lua", "modified item path")
  assert_eq(#unknown.items, 1, "unknown section item count")
  assert_eq(#updated.items, 1, "updated section item count")
end
