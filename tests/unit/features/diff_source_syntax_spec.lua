local syntax = require("cvs.features.diff.source_syntax")

return function()
  local diff = {
    "@@ -1,2 +1,2 @@",
    "-local old = 1",
    "+local new = 2",
    " return new",
    "\\ No newline at end of file",
    "@@ -10 +10 @@",
    "-local gone = 1",
    "+local added = 1",
  }
  local hunks = syntax._hunks(diff, 1000, 262144)
  assert(#hunks == 2, "separate hunks parsed independently")
  assert(hunks[1].old.lines[1] == "local old = 1" and hunks[1].old.rows[1] == 2, "old lines mapped to diff")
  assert(hunks[1].new.lines[1] == "local new = 2" and hunks[1].new.rows[1] == 3, "new lines mapped to diff")
  assert(#hunks[1].old.lines == 2 and #hunks[1].new.lines == 2, "context on both sides, marker excluded")
  assert(#syntax._hunks(diff, 4, 262144) == 1, "line budget bounds parsing")
  assert(#syntax._hunks(diff, 1000, 20) == 1, "byte budget bounds parsing")
  assert(#syntax.captures(diff, "/tmp/file.unknown_language_123") == 0, "missing parser uses diff fallback")

  local lang = vim.treesitter.language.get_lang("lua")
  if not lang or not pcall(vim.treesitter.get_string_parser, "local x = 1", lang)
    or not vim.treesitter.query.get(lang, "highlights") then
    return -- optional parser / query is not installed
  end
  local tokens = syntax.captures(diff, "/tmp/file.lua")
  local old_keyword, new_keyword = false, false
  for _, token in ipairs(tokens) do
    if token.capture == "keyword" and token.row == 2 and token.start_col == 0 then old_keyword = true end
    if token.capture == "keyword" and token.row == 3 and token.start_col == 0 then new_keyword = true end
  end
  assert(old_keyword and new_keyword, "source syntax tokens map onto old and new diff rows")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff)
  local ns = vim.api.nvim_create_namespace("cvs-log-syntax-test")
  syntax.apply(buf, ns, tokens, function(row) return row end, 1)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local found = false
  for _, mark in ipairs(marks) do
    if mark[2] == 1 and mark[3] == 1 and mark[4].hl_group == "CvsDiffSyntaxkeyword_lua" then
      local hl = vim.api.nvim_get_hl(0, { name = mark[4].hl_group, link = false })
      assert(hl.bg == nil, "source syntax groups preserve diff backgrounds")
      found = true
    end
  end
  assert(found, "source highlight overlays begin after the diff prefix")
  vim.api.nvim_buf_delete(buf, { force = true })
end
