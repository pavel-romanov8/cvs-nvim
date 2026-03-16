local service = require("cvs.features.session.service")

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
    generated_at = "2026-03-16 12:00:00",
    files = {
      { code = "M", path = "lua/cvs/init.lua", status = "modified" },
      { code = "A", path = "lua/cvs/new.lua", status = "added" },
      { code = "R", path = "lua/cvs/old.lua", status = "removed" },
      { code = "?", path = "notes.txt", status = "unknown" },
      { code = "C", path = "plugin/cvs.lua", status = "conflict" },
      { code = "U", path = "README.md", status = "updated" },
    },
  }

  local initial = service._build_view_state(snapshot, {}, {})
  assert_eq(initial.selectable_count, 3, "initial selectable count")
  assert_eq(initial.selected_count, 3, "initial selected count")
  assert_eq(initial.selected["lua/cvs/init.lua"], true, "modified file selected by default")
  assert_eq(initial.selected["lua/cvs/new.lua"], true, "added file selected by default")
  assert_eq(initial.selected["lua/cvs/old.lua"], true, "removed file selected by default")

  local outgoing = find_section(initial, "outgoing")
  local attention = find_section(initial, "attention")
  local incoming = find_section(initial, "incoming")
  assert_eq(#outgoing.items, 3, "outgoing section item count")
  assert_eq(#attention.items, 2, "attention section item count")
  assert_eq(#incoming.items, 1, "incoming section item count")

  local next = service._build_view_state(snapshot, {}, {
    selected = {
      ["lua/cvs/init.lua"] = false,
      ["lua/cvs/new.lua"] = true,
      ["lua/cvs/old.lua"] = true,
    },
  })

  assert_eq(next.selected_count, 2, "updated selected count")
  assert_eq(next.selected["lua/cvs/init.lua"], false, "modified file selection is preserved")
end
