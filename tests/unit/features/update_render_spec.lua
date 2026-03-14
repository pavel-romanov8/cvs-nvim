local render = require("cvs.features.update.render")

local function assert_match(text, pattern, message)
  if not text:find(pattern, 1, true) then
    error(("%s: missing %q in %q"):format(message, pattern, text))
  end
end

return function()
  local lines = render.lines({
    phase = "done",
    workspace = {
      root_dir = "/tmp/example",
    },
    scope_label = "workspace",
    started_at = "2026-03-14 10:00:00",
    completed_at = "2026-03-14 10:00:05",
    command = { "cvs", "-q", "update" },
    result = {
      code = 0,
      duration_ms = 1234,
    },
    parsed = {
      items = {
        { code = "U", path = "README.md", status = "updated" },
        { code = "C", path = "plugin/cvs.lua", status = "conflict" },
      },
      summary = {
        updated = 1,
        patched = 0,
        modified = 0,
        added = 0,
        removed = 0,
        conflict = 1,
        unknown = 0,
      },
      has_conflicts = true,
    },
    messages = {
      "cvs update: warning: plugin/cvs.lua already contains conflict markers",
    },
  })

  local text = table.concat(lines, "\n")
  assert_match(text, "CVS Update", "header")
  assert_match(text, "Completed", "completed phase")
  assert_match(text, "Updated: 1", "updated summary")
  assert_match(text, "Conflicts: 1", "conflict summary")
  assert_match(text, "C  plugin/cvs.lua", "conflict file line")
  assert_match(text, "run :CvsConflicts", "conflict hint")
end
