local parse = require("cvs.features.log.parse")
local render = require("cvs.features.log.render")

return function(root)
  local result = parse.parse(vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-basic.txt"))
  assert(#result.entries == 3, "all revisions parsed")
  assert(result.header.head == "1.3", "head parsed")
  assert(result.entries[1].author == "mary", "author parsed")
  assert(result.entries[1].date == "2026/01/03 11:22:33", "date parsed")
  assert(result.entries[1].lines == "+2 -1", "line count parsed")
  assert(result.entries[1].commit_id == "ABC123", "shared commit ID parsed")
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

  local workspace = parse.parse_scope(
    vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-workspace.txt"),
    { scope_path = "/tmp/project", logging_prefix = "project" }
  )
  assert(#workspace.files == 2, "recursive log files parsed")
  assert(#workspace.commits == 3, "revisions grouped into commits")
  assert(workspace.commits[1].id == "ABC123", "commits sorted newest first")
  assert(#workspace.commits[1].files == 2, "shared commit groups all affected files")
  assert(workspace.commits[1].files[2].path == "pkg/helper.lua", "logging directory retained in path")
  assert(workspace.commits[1].files[2].absolute_path == "/tmp/project/pkg/helper.lua", "absolute path retained")
  local without_progress = {}
  for _, line in ipairs(vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-workspace.txt")) do
    if not line:match("^cvs rlog: Logging") then without_progress[#without_progress + 1] = line end
  end
  local derived = parse.parse_scope(without_progress, {
    scope_path = "/tmp/project",
    logging_prefix = "project",
  })
  assert(derived.commits[1].files[2].path == "pkg/helper.lua", "RCS archive path recovers paths when progress is on stderr")
  assert(parse.find_commit(workspace, "ABC123") == workspace.commits[1], "commit can be found by exact ID")
  assert(workspace.commits[3].id == nil, "missing commit IDs are not guessed from metadata")

  local lines, row_map = render.lines({ target_path = "/tmp/file.lua", parsed = result })
  local found = false
  for row, entry in pairs(row_map) do
    if entry.revision == "1.2" and lines[row]:match("^revision 1%.2") then
      found = true
    end
  end
  assert(found, "revision header can be selected")

  local project_lines, project_map = render.lines({
    scope_kind = "directory",
    scope_path = "/tmp/project",
    loading = false,
    parsed = workspace,
    expanded = { ABC123 = true },
  })
  assert(table.concat(project_lines, "\n"):find("commit ABC123", 1, true), "project log renders commit groups")
  assert(table.concat(project_lines, "\n"):find("pkg/helper.lua", 1, true), "expanded commit renders affected files")
  local mapped_commit = false
  for _, target in pairs(project_map) do
    if target.kind == "commit" and target.commit.id == "ABC123" then mapped_commit = true end
  end
  assert(mapped_commit, "project commit header can be selected")
end
