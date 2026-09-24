local service = require("cvs.features.revert.service")
local runner = require("cvs.cvs.runner")
local capabilities = require("cvs.cvs.capabilities")
local events = require("cvs.core.events")
local state = require("cvs.core.state")
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
  local old_run, old_detect, old_notify, old_emit = runner.run, capabilities.detect, util.notify, events.emit
  local old_confirm = service._confirm
  util.notify = function() end
  events.emit = function() end
  service._confirm = function() return true end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/CVS", "p")
  vim.fn.mkdir(tmp .. "/pkg/CVS", "p")
  vim.fn.writefile({ "/repo" }, tmp .. "/CVS/Root")
  vim.fn.writefile({ "project" }, tmp .. "/CVS/Repository")
  vim.fn.writefile({ "/file.lua/1.4///" }, tmp .. "/CVS/Entries")
  vim.fn.writefile({ "/helper.lua/1.9///" }, tmp .. "/pkg/CVS/Entries")
  vim.fn.writefile({ "/repo" }, tmp .. "/pkg/CVS/Root")
  vim.fn.writefile({ "project/pkg" }, tmp .. "/pkg/CVS/Repository")

  local calls = {}
  capabilities.detect = function() return { executable = true } end
  runner.run = function(command, opts, callback)
    local call = { command = command, opts = opts, callback = callback }
    calls[#calls + 1] = call
    return { kill = function() call.killed = true end }
  end

  local ok, err = pcall(function()
    local bufnr = service.open({ workspace = {
      root_dir = tmp,
      repository = "project",
    }, commit_id = "ABC123" })
    assert(text(bufnr):find("Discovering every file", 1, true), "revert opens while discovering changeset")
    assert(calls[1].command[#calls[1].command - 1] == "rlog", "revert discovers repository-wide changes")
    assert(calls[1].command[#calls[1].command] == "project", "revert discovery targets the workspace module")

    calls[1].callback({
      code = 0,
      signal = 0,
      stdout = vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-workspace.txt"),
      stderr = {},
    })
    assert(calls[2].command[#calls[2].command - 1] == "file.lua"
      or calls[2].command[#calls[2].command] == "pkg/helper.lua", "revert preflights affected files")
    calls[2].callback({ code = 0, signal = 0, stdout = {}, stderr = {} })

    local view = state.get_buffer(bufnr).view_state
    assert(view.phase == "ready", "clean changeset becomes ready")
    assert(#view.items == 2, "all files sharing the commit ID are included")
    assert(text(bufnr):find("reverse merge 1.3 -> 1.2", 1, true), "revert plan explains reverse revisions")
    assert(service.copy_commit_id(bufnr) == "ABC123", "revert ID can be copied")

    local revert_win = vim.fn.bufwinid(bufnr)
    vim.api.nvim_win_set_cursor(revert_win, { row_for(bufnr, "file.lua"), 0 })
    local diff_bufnr = service.preview(bufnr)
    assert(table.concat(calls[3].command, " "):find("diff %-u %-r 1%.3 %-r 1%.2 file%.lua"),
      "revert preview reverses the revision order")
    calls[3].callback({
      code = 1,
      signal = 0,
      stdout = { "@@ -1 +1 @@", "-bad", "+good" },
      stderr = {},
    })
    assert(text(diff_bufnr):find("+good", 1, true), "reverse preview is rendered")
    vim.api.nvim_buf_delete(diff_bufnr, { force = true })
    vim.api.nvim_set_current_win(revert_win)

    assert(service.apply(bufnr, false) == true, "ready revert starts applying")
    assert(table.concat(calls[4].command, " "):find("%-nq update"), "affected files are rechecked before mutation")
    calls[4].callback({ code = 0, signal = 0, stdout = {}, stderr = {} })
    assert(table.concat(calls[5].command, " "):find("update %-j 1%.3 %-j 1%.2 file%.lua"),
      "first file is reverse merged")
    calls[5].callback({ code = 0, signal = 0, stdout = {}, stderr = {} })
    assert(table.concat(calls[6].command, " "):find("update %-j 1%.8 %-j 1%.7 pkg/helper%.lua"),
      "second file is reverse merged")
    calls[6].callback({ code = 0, signal = 0, stdout = {}, stderr = {} })
    assert(view.phase == "applied", "successful reverse merges remain local for review")
    assert(text(bufnr):find("Revert applied locally", 1, true), "applied state is visible")
  end)

  runner.run, capabilities.detect, util.notify, events.emit = old_run, old_detect, old_notify, old_emit
  service._confirm = old_confirm
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.fn.delete(tmp, "rf")
  if not ok then error(err) end
end
