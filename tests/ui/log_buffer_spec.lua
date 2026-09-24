local service = require("cvs.features.log.service")
local runner = require("cvs.cvs.runner")
local capabilities = require("cvs.cvs.capabilities")
local log_buffer = require("cvs.features.log.buffer")
local util = require("cvs.core.util")

local function text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function row_for(bufnr, needle)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find(needle, 1, true) then return row end
  end
end

return function(root)
  local old_run, old_detect, old_notify = runner.run, capabilities.detect, util.notify
  util.notify = function() end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/CVS", "p")
  vim.fn.writefile({ "/repo" }, tmp .. "/CVS/Root")
  vim.fn.writefile({ "repo" }, tmp .. "/CVS/Repository")
  vim.fn.writefile({ "/file.lua/1.3///" }, tmp .. "/CVS/Entries")
  vim.fn.writefile({ "local x = 1" }, tmp .. "/file.lua")

  local calls = {}
  capabilities.detect = function() return { executable = true } end
  runner.run = function(command, opts, callback)
    local call = { command = command, opts = opts, callback = callback }
    calls[#calls + 1] = call
    return { kill = function() call.killed = true end }
  end
  local fixture = vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-basic.txt")
  local change = { "Index: file.lua", "--- file.lua", "+++ file.lua", "@@ -1 +1 @@", "-old", "+new" }

  local ok, err = pcall(function()
    local bufnr, winid = service.open({ path = tmp .. "/file.lua" })
    assert(text(bufnr):find("Loading CVS log", 1, true), "file log opens before CVS completes")
    calls[1].callback({ code = 0, signal = 0, stdout = fixture, stderr = {} })
    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "revision 1.2 "), 0 })
    assert(log_buffer.current(bufnr).revision == "1.2" and text(bufnr):find("commit: DEF456", 1, true),
      "file log maps rendered revisions and commit IDs")
    assert(service.copy_commit_id(bufnr) == "DEF456" and vim.fn.getreg('"') == "DEF456",
      "selected commit ID can be copied")

    local full_buf = service.open_revision(bufnr)
    assert(text(full_buf):find("Loading revision diff", 1, true)
      and table.concat(calls[2].command, " "):match("diff %-u %-r 1%.1 %-r 1%.2 file%.lua$"),
      "full revision diff opens immediately with the correct predecessor")
    calls[2].callback({ code = 1, signal = 0, stdout = change, stderr = {} })
    assert(vim.bo[full_buf].readonly and text(full_buf):find("+new", 1, true)
      and not text(full_buf):find("Index: file.lua", 1, true), "full diff is immutable and hides CVS preamble")

    vim.api.nvim_set_current_win(winid)
    service.toggle_preview(bufnr)
    calls[3].callback({ code = 1, signal = 0, stdout = change, stderr = {} })
    assert(text(bufnr):find("| +new", 1, true), "inline preview renders the same revision diff")
    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "| +new"), 0 })
    assert(log_buffer.current(bufnr).revision == "1.2" and service.toggle_preview(bufnr) == false,
      "inline rows retain revision identity and toggle closed")

    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "revision 1.1 "), 0 })
    local first_buf = service.open_revision(bufnr)
    assert(table.concat(calls[4].command, " "):match("update %-p %-r 1%.1 file%.lua$"),
      "initial revision is loaded against an empty base")
    calls[4].callback({ code = 0, signal = 0, stdout = { "initial" }, stdout_ends_with_newline = true, stderr = {} })
    assert(text(first_buf):find("+initial", 1, true), "initial revision is displayed as additions")

    vim.api.nvim_set_current_win(winid)
    local abandoned = service.open_revision(bufnr)
    vim.api.nvim_buf_delete(abandoned, { force = true })
    assert(calls[5].killed, "closing a loading revision diff cancels CVS")
  end)

  runner.run, capabilities.detect, util.notify = old_run, old_detect, old_notify
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.fn.delete(tmp, "rf")
  if not ok then error(err) end
end
