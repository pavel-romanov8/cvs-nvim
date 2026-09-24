local render = require("cvs.features.status.render")

local function contains(lines, needle)
  return table.concat(lines, "\n"):find(needle, 1, true) ~= nil
end

return function()
  local lines, row_map, highlights, syntax_rows = render.lines({
    workspace = { root_dir = "/tmp/example" },
    scope_label = "workspace",
    generated_at = "2026-03-27 12:00:00",
    cached = true,
    total_count = 4,
    selectable_count = 2,
    selected_count = 1,
    counts = { modified = 1, added = 1, missing = 1, unknown = 1 },
    sections = {
      {
        kind = "selected",
        title = "Selected",
        items = {
          { code = "A", path = "new.lua", status = "added", selectable = true, selected = true },
        },
      },
      {
        kind = "modified",
        title = "Modified",
        items = {
          { code = "M", path = "changed.lua", status = "modified", selectable = true },
        },
      },
      {
        kind = "missing",
        title = "Missing",
        items = {
          { code = "R", path = "missing.lua", status = "missing" },
        },
      },
      {
        kind = "unknown",
        title = "Unknown",
        items = {
          { code = "?", path = "notes.txt", status = "unknown" },
        },
      },
    },
    inline_diff = {
      path = "changed.lua",
      lines = { "@@ -1 +1 @@", "-old", "+new" },
    },
  })

  assert(contains(lines, "Root: /tmp/example") and contains(lines, "Commit selection: 1/2"),
    "status renders workspace and selection summary")
  assert(contains(lines, "Selected (1)") and contains(lines, "M  changed.lua") and contains(lines, "?  notes.txt"),
    "status renders grouped CVS states")
  assert(contains(lines, "   @@ -1 +1 @@") and contains(lines, "   +new"),
    "status embeds the active inline diff")

  local target_kinds = {}
  for _, target in pairs(row_map) do target_kinds[target.kind] = true end
  assert(target_kinds.section and target_kinds.file, "rendered rows retain semantic action targets")

  local groups = {}
  for _, highlight in ipairs(highlights) do groups[highlight.group] = true end
  assert(groups.CvsStatusModified and groups.CvsStatusAdded and groups.CvsStatusMissing,
    "CVS states retain distinct highlights")
  assert(groups.CvsDiffChange and groups.CvsDiffDelete and groups.CvsDiffAdd,
    "inline diff retains semantic highlights")
  assert(lines[syntax_rows[2]] == "   -old" and lines[syntax_rows[3]] == "   +new",
    "source syntax rows map back to diff content")

  local error_lines = render.lines({
    workspace = { root_dir = "/tmp/example" },
    scope_label = "workspace",
    error = "status_failed: CVS status exited with code 124.",
  })
  assert(contains(error_lines, "Status unavailable: status_failed")
    and not contains(error_lines, "Working copy is clean"), "status failures cannot look like a clean workspace")

  local warning_lines = render.lines({
    workspace = { root_dir = "/tmp/example" },
    scope_label = "workspace",
    total_count = 1,
    selectable_count = 0,
    selected_count = 0,
    counts = { unknown = 1 },
    sections = {},
    warning = "Status incomplete: CVS exited with code 1; showing the status entries it returned.",
  })
  assert(contains(warning_lines, "Status incomplete: CVS exited with code 1"),
    "partial status remains visibly incomplete")
end
