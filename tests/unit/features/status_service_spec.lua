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
  assert_eq(view_state.total_count, 5, "visible file count")
  assert_eq(view_state.counts.modified, 1, "modified count")
  assert_eq(view_state.counts.unknown, 1, "unknown count")
  assert_eq(view_state.counts.updated, nil, "updated count is hidden")
  assert_eq(view_state.messages[1], "status warning", "messages are preserved")
  assert_eq(view_state.selectable_count, 3, "committable file count")
  assert_eq(view_state.selected_count, 0, "initial selection is empty")

  local modified = find_section(view_state, "modified")
  local unknown = find_section(view_state, "unknown")
  local updated = find_section(view_state, "updated")

  assert_eq(#modified.items, 1, "modified section item count")
  assert_eq(modified.items[1].path, "lua/cvs/init.lua", "modified item path")
  assert_eq(modified.items[1].selectable, true, "modified item is selectable")
  assert_eq(modified.items[1].selected, false, "modified item starts unselected")
  assert_eq(#unknown.items, 1, "unknown section item count")
  assert_eq(unknown.items[1].selectable, false, "unknown item is not selectable")
  assert_eq(updated, nil, "updated section is hidden")

  local selected = service._build_view_state(snapshot, {}, {
    selected = {
      ["lua/cvs/init.lua"] = true,
      ["notes.txt"] = true,
      ["missing.lua"] = true,
    },
  })
  assert_eq(selected.selected_count, 1, "only eligible paths remain selected")
  assert_eq(selected.selected["lua/cvs/init.lua"], true, "eligible selection is preserved")
  assert_eq(selected.selected["notes.txt"], nil, "unknown selection is removed")
  assert_eq(selected.selected["missing.lua"], nil, "missing selection is removed")
  local selected_section = find_section(selected, "selected")
  assert_eq(#selected_section.items, 1, "selected files have a dedicated section")
  assert_eq(selected_section.items[1].path, "lua/cvs/init.lua", "selected section contains the selected file")
  assert_eq(selected.sections[1].kind, "selected", "selected section is rendered first")
  assert_eq(find_section(selected, "modified"), nil, "selected files leave their status section")

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir .. "/CVS", "p")
  vim.fn.writefile({
    "/tracked.lua/1.7/Thu Jan 01 00:00:00 2026//",
    "/present.lua/1.4/Thu Jan 01 00:00:00 2026//",
  }, temp_dir .. "/CVS/Entries")
  vim.fn.writefile({ "content" }, temp_dir .. "/present.lua")
  local reconciled = service._reconcile_working_copy({
    { code = "U", path = "tracked.lua", status = "updated" },
    { code = "U", path = "present.lua", status = "updated" },
    { code = "U", path = "incoming.lua", status = "updated" },
  }, {
    root_dir = temp_dir,
  })
  assert_eq(reconciled[1].code, "!", "missing tracked file gets a distinct status code")
  assert_eq(reconciled[1].status, "missing", "missing tracked file is not treated as incoming")
  assert_eq(reconciled[2].status, "updated", "present tracked file remains incoming")
  assert_eq(reconciled[3].status, "updated", "untracked incoming file remains incoming")

  local missing_view = service._build_view_state({
    workspace = { root_dir = temp_dir },
    files = reconciled,
  }, {}, {})
  local missing = find_section(missing_view, "missing")
  assert_eq(#missing.items, 1, "missing tracked file is visible")
  assert_eq(missing.items[1].selectable, false, "missing file must be scheduled before commit")
  assert_eq(missing_view.total_count, 1, "incoming file remains hidden from status")
  vim.fn.delete(temp_dir, "rf")
end
