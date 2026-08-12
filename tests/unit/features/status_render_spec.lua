local render = require("cvs.features.status.render")

local function assert_match(text, pattern, message)
  if not text:find(pattern, 1, true) then
    error(("%s: missing %q in %q"):format(message, pattern, text))
  end
end

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  local lines, row_map, highlights = render.lines({
    workspace = {
      root_dir = "/tmp/example",
    },
    scope_label = "workspace",
    generated_at = "2026-03-27 12:00:00",
    cached = true,
    total_count = 5,
    selectable_count = 2,
    selected_count = 1,
    counts = {
      modified = 1,
      added = 1,
      missing = 1,
      removed = 1,
      unknown = 1,
    },
    sections = {
      {
        kind = "selected",
        title = "Selected",
        selectable_count = 1,
        selected_count = 1,
        items = {
          { code = "A", path = "lua/cvs/new.lua", status = "added", selectable = true, selected = true },
        },
      },
      {
        kind = "modified",
        title = "Modified",
        selectable_count = 1,
        selected_count = 0,
        items = {
          { code = "M", path = "lua/cvs/init.lua", status = "modified", selectable = true, selected = false },
        },
      },
      {
        kind = "missing",
        title = "Missing",
        items = {
          { code = "R", path = "lua/cvs/missing.lua", status = "missing", selectable = false, selected = false },
        },
      },
      {
        kind = "unknown",
        title = "Unknown",
        items = {
          { code = "?", path = "notes.txt", status = "unknown", selectable = false, selected = false },
        },
      },
    },
    messages = {
      "example warning",
    },
    inline_diff = {
      path = "lua/cvs/init.lua",
      lines = {
        "@@ -1 +1 @@",
        "-local old = true",
        "+local new = true",
      },
    },
  })

  local text = table.concat(lines, "\n")
  assert_match(text, "CVS", "header")
  assert_match(text, "Root: /tmp/example", "root line")
  assert_match(text, "Files: 5", "file count")
  assert_match(text, "Commit selection: 1/2", "commit selection count")
  assert_match(text, "Snapshot: 2026-03-27 12:00:00 (cached)", "cached snapshot marker")
  assert_match(text, "M: 1, A: 1, R: 2, ?: 1", "summary counts")
  assert_match(text, "Selected (1)", "selected section")
  assert_match(text, "Modified (1)", "modified section")
  assert_match(text, "Missing (1)", "missing section")
  assert_match(text, "    M  lua/cvs/init.lua", "unselected file line")
  assert_match(text, "    A  lua/cvs/new.lua", "selected file line")
  assert_match(text, "    R  lua/cvs/missing.lua", "missing file line")
  assert_true(not text:find("[ ]", 1, true), "unselected files do not use checkboxes")
  assert_true(not text:find("[x]", 1, true), "selected files do not use checkboxes")
  assert_match(text, "    ?  notes.txt", "non-selectable file line")
  assert_match(text, "   @@ -1 +1 @@", "inline diff hunk")
  assert_match(text, "   -local old = true", "inline diff deletion")
  assert_match(text, "   +local new = true", "inline diff addition")
  assert_true(not text:find("Messages", 1, true), "messages section is hidden")
  assert_true(not text:find("example warning", 1, true), "status messages are hidden")
  assert_match(text, "<CR> opens the current file", "help line")
  assert_match(text, "- toggles the commit selection", "selection help line")
  assert_match(text, "cc opens a commit message for the selected files", "commit help line")
  assert_match(text, "A adds unknown files as binary (-kb)", "binary add help line")

  local targets = {}
  for row, target in pairs(row_map) do
    targets[target.kind] = targets[target.kind] or {}
    targets[target.kind][#targets[target.kind] + 1] = { row = row, target = target }
  end
  assert_true(#targets.section == 4, "section rows are semantic targets")
  assert_true(#targets.file == 7, "file and inline diff rows are semantic targets")

  local groups = {}
  for _, highlight in ipairs(highlights) do
    groups[highlight.group] = true
  end
  assert_true(groups.CvsHeader, "header highlight")
  assert_true(groups.CvsSection, "section highlight")
  assert_true(groups.CvsStatusModified, "modified file highlight")
  assert_true(groups.CvsStatusAdded, "added file highlight")
  assert_true(groups.CvsStatusMissing, "missing file highlight")
  assert_true(groups.DiffChange, "inline diff hunk highlight")
  assert_true(groups.DiffDelete, "inline diff deletion highlight")
  assert_true(groups.DiffAdd, "inline diff addition highlight")

  local error_lines = render.lines({
    workspace = { root_dir = "/tmp/example" },
    scope_label = "workspace",
    error = "status_failed: CVS status exited with code 124.",
  })
  local error_text = table.concat(error_lines, "\n")
  assert_match(error_text, "Status unavailable: status_failed", "status failure")
  assert_true(not error_text:find("Working copy is clean", 1, true), "failed status is not reported as clean")

  local warning_lines = render.lines({
    workspace = { root_dir = "/tmp/example" },
    scope_label = "workspace",
    total_count = 1,
    selectable_count = 0,
    selected_count = 0,
    counts = { unknown = 1 },
    sections = {},
    warning = "Status incomplete: CVS skipped 1 missing directory; files beneath it may be absent.",
  })
  local warning_text = table.concat(warning_lines, "\n")
  assert_match(warning_text, "Status incomplete: CVS skipped 1 missing directory", "partial status warning")
end
