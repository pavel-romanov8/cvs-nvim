local service = require("cvs.features.status.service")

local function section(view_state, kind)
  for _, value in ipairs(view_state.sections or {}) do
    if value.kind == kind then return value end
  end
end

return function()
  local snapshot = {
    workspace = { root_dir = "/tmp/example" },
    generated_at = "2026-03-27 12:00:00",
    files = {
      { code = "M", path = "init.lua", status = "modified" },
      { code = "A", path = "new.lua", status = "added" },
      { code = "R", path = "old.lua", status = "removed" },
      { code = "?", path = "notes.txt", status = "unknown" },
      { code = "?", path = ".#init.lua.1.4", status = "unknown" },
      { code = "C", path = "plugin.lua", status = "conflict" },
      { code = "U", path = "README.md", status = "updated" },
    },
    messages = { "status warning" },
  }

  local view = service._build_view_state(snapshot, {}, {})
  assert(view.total_count == 6 and view.selectable_count == 3 and view.selected_count == 0,
    "status model counts visible and committable files")
  assert(view.counts.backup == 1 and view.counts.updated == nil,
    "backups are visible while incoming-only files remain hidden")
  assert(section(view, "modified").items[1].selectable and not section(view, "unknown").items[1].selectable,
    "only committable CVS states are selectable")
  assert(section(view, "backup").items[1].is_cvs_backup, "CVS recovery files have a dedicated action type")

  local selected = service._build_view_state(snapshot, {}, {
    selected = { ["init.lua"] = true, ["notes.txt"] = true, ["missing.lua"] = true },
  })
  assert(selected.selected_count == 1 and selected.selected["init.lua"],
    "refresh preserves only eligible selections")
  assert(not selected.selected["notes.txt"] and not selected.selected["missing.lua"],
    "refresh drops unknown and absent selections")
  assert(selected.sections[1].kind == "selected" and section(selected, "modified") == nil,
    "selected files move into the leading selected section")

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
  }, { root_dir = temp_dir })
  assert(reconciled[1].status == "missing" and reconciled[2].status == "updated",
    "metadata distinguishes deleted tracked files from incoming updates")
  local missing_view = service._build_view_state({
    workspace = { root_dir = temp_dir },
    files = reconciled,
  }, {}, {})
  assert(#section(missing_view, "missing").items == 1 and missing_view.total_count == 1,
    "only the missing working file is promoted into status")

  vim.fn.mkdir(temp_dir .. "/nested", "p")
  vim.fn.writefile({ "recovery" }, temp_dir .. "/.#tracked.lua.1.6")
  vim.fn.writefile({ "nested recovery" }, temp_dir .. "/nested/.#other.lua.1.2")
  local backups = service._append_cvs_backups({
    { code = "?", path = ".#tracked.lua.1.6", status = "unknown" },
  }, { root_dir = temp_dir }, {})
  assert(#backups == 2 and backups[1].is_cvs_backup and backups[2].is_cvs_backup,
    "backup scan deduplicates CVS output and marks every recovery file")
  assert(backups[2].path == "nested/.#other.lua.1.2", "backup paths remain workspace-relative")

  local scoped = service._append_cvs_backups({}, { root_dir = temp_dir }, { path = "tracked.lua" })
  assert(#scoped == 1 and scoped[1].path == ".#tracked.lua.1.6",
    "file-scoped status includes only matching recovery files")
  vim.fn.delete(temp_dir, "rf")
end
