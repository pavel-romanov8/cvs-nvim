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
  local lines, _, highlights = render.lines({
    workspace = {
      root_dir = "/tmp/example",
    },
    scope_label = "workspace",
    generated_at = "2026-03-27 12:00:00",
    cached = true,
    total_count = 4,
    counts = {
      modified = 1,
      added = 1,
      removed = 1,
      unknown = 1,
    },
    sections = {
      {
        kind = "modified",
        title = "Modified",
        items = {
          { code = "M", path = "lua/cvs/init.lua", status = "modified" },
        },
      },
      {
        kind = "added",
        title = "Added",
        items = {
          { code = "A", path = "lua/cvs/new.lua", status = "added" },
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
  assert_match(text, "Files: 4", "file count")
  assert_match(text, "Snapshot: 2026-03-27 12:00:00 (cached)", "cached snapshot marker")
  assert_match(text, "M: 1, A: 1, R: 1, ?: 1", "summary counts")
  assert_match(text, "Modified (1)", "modified section")
  assert_match(text, "M  lua/cvs/init.lua", "modified file line")
  assert_match(text, "   @@ -1 +1 @@", "inline diff hunk")
  assert_match(text, "   -local old = true", "inline diff deletion")
  assert_match(text, "   +local new = true", "inline diff addition")
  assert_true(not text:find("Messages", 1, true), "messages section is hidden")
  assert_true(not text:find("example warning", 1, true), "status messages are hidden")
  assert_match(text, "<CR> opens the current file", "help line")

  local groups = {}
  for _, highlight in ipairs(highlights) do
    groups[highlight.group] = true
  end
  assert_true(groups.CvsHeader, "header highlight")
  assert_true(groups.CvsSection, "section highlight")
  assert_true(groups.CvsStatusModified, "modified file highlight")
  assert_true(groups.CvsStatusAdded, "added file highlight")
  assert_true(groups.DiffChange, "inline diff hunk highlight")
  assert_true(groups.DiffDelete, "inline diff deletion highlight")
  assert_true(groups.DiffAdd, "inline diff addition highlight")
end
