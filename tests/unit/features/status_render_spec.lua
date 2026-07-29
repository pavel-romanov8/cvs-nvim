local render = require("cvs.features.status.render")

local function assert_match(text, pattern, message)
  if not text:find(pattern, 1, true) then
    error(("%s: missing %q in %q"):format(message, pattern, text))
  end
end

return function()
  local lines = render.lines({
    workspace = {
      root_dir = "/tmp/example",
    },
    scope_label = "workspace",
    generated_at = "2026-03-27 12:00:00",
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
  })

  local text = table.concat(lines, "\n")
  assert_match(text, "CVS", "header")
  assert_match(text, "Root: /tmp/example", "root line")
  assert_match(text, "Files: 4", "file count")
  assert_match(text, "M: 1, A: 1, R: 1, ?: 1", "summary counts")
  assert_match(text, "Modified (1)", "modified section")
  assert_match(text, "M  lua/cvs/init.lua", "modified file line")
  assert_match(text, "Messages", "messages section")
  assert_match(text, "<CR> opens the current file", "help line")
end
