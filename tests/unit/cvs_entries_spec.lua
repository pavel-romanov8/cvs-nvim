local entries = require("cvs.cvs.entries")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir .. "/CVS", "p")

  local path = temp_dir .. "/CVS/Entries"
  local old_entry = "/file.lua/1.6/Thu Jan 01 00:00:00 2026//"
  local new_entry = "/file.lua/1.7/Fri Jan 02 00:00:00 2026//"
  vim.fn.writefile({ old_entry }, path)
  vim.fn.writefile({ "R " .. old_entry, "A " .. new_entry, "X ignored" }, path .. ".Log")

  local loaded = entries.load(path)
  assert_eq(#loaded, 1, "Entries.Log operations are applied")
  assert_eq(loaded[1].revision, "1.7", "Entries.Log updates the working revision")
  assert_eq(entries.working_revision(temp_dir .. "/file.lua"), "1.7", "working revision is found by file path")
  assert_eq(entries.valid_revision("1.7.2.1"), true, "branch revision is valid")
  assert_eq(entries.valid_revision("0"), false, "added file has no base revision")

  vim.fn.delete(temp_dir, "rf")
end
