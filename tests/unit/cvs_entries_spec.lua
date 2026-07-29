local entries = require("cvs.cvs.entries")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")

  local path = temp_dir .. "/Entries"
  local old_entry = "/file.lua/1.6/Thu Jan 01 00:00:00 2026//"
  local new_entry = "/file.lua/1.7/Fri Jan 02 00:00:00 2026//"
  vim.fn.writefile({ old_entry }, path)
  vim.fn.writefile({ "R " .. old_entry, "A " .. new_entry, "X ignored" }, path .. ".Log")

  local loaded = entries.load(path)
  assert_eq(#loaded, 1, "Entries.Log operations are applied")
  assert_eq(loaded[1].revision, "1.7", "Entries.Log updates the working revision")

  vim.fn.delete(temp_dir, "rf")
end
