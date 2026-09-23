local parse = require("cvs.features.log.parse")
local render = require("cvs.features.log.render")

return function(root)
  local result = parse.parse(vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-basic.txt"))
  assert(#result.entries == 3, "all revisions parsed")
  assert(result.header.head == "1.3", "head parsed")
  assert(result.entries[1].author == "mary", "author parsed")
  assert(result.entries[1].date == "2026/01/03 11:22:33", "date parsed")
  assert(result.entries[1].lines == "+2 -1", "line count parsed")
  assert(table.concat(result.entries[1].message, "\n") == "Fix a tricky bug.\n\nRetain this paragraph.", "multiline message preserved")
  assert(result.entries[2].tags[1] == "RELEASE_1", "symbolic name attached")
  assert(result.entries[3].state == "dead", "dead revision parsed")
  local branch = parse.parse({
    "symbolic names:", "  FEATURE: 1.2.0.2", "description:", "----------------------------",
    "revision 1.2.2.1", "date: 2026/01/04 11:00:00;  author: joe;  state: Exp;",
    "branches: 1.2.2;", "Branch work", "============================",
  })
  assert(branch.entries[1].tags[1] == "FEATURE (branch)", "branch symbolic name attached")
  assert(branch.entries[1].branches == "1.2.2;", "revision branch metadata parsed")
  assert(parse.predecessor("1.7") == "1.6", "trunk predecessor")
  assert(parse.predecessor("1.3.2.2") == "1.3.2.1", "branch predecessor")
  assert(parse.predecessor("1.3.2.1") == "1.3", "branch point predecessor")
  assert(parse.predecessor("1.1") == nil, "initial revision has no predecessor")

  local lines, row_map = render.lines({ target_path = "/tmp/file.lua", parsed = result })
  local found = false
  for row, entry in pairs(row_map) do
    if entry.revision == "1.2" and lines[row]:match("^revision 1%.2") then
      found = true
    end
  end
  assert(found, "revision header can be selected")
end
