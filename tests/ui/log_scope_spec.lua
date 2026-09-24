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
  vim.fn.writefile({ "project" }, tmp .. "/CVS/Repository")
  vim.fn.writefile({ "local x = 1" }, tmp .. "/file.lua")
  local calls = {}
  capabilities.detect = function() return { executable = true } end
  runner.run = function(command, opts, callback)
    local call = { command = command, opts = opts, callback = callback }
    calls[#calls + 1] = call
    return { kill = function() call.killed = true end }
  end

  local ok, err = pcall(function()
    local forced = service._prepare({ path = tmp .. "/file.lua", force = true })
    assert(forced.scope_kind == "directory" and forced.scope_path == tmp,
      "bang widens a file context to the workspace root")

    local bufnr, winid = service.open({ path = tmp })
    assert(calls[1].opts.cwd == tmp, "directory log runs from the workspace")
    assert(calls[1].command[#calls[1].command] == "project", "directory log targets the repository module")
    assert(calls[1].command[#calls[1].command - 1] == "rlog", "directory log includes removed repository files")
    calls[1].callback({
      code = 0,
      signal = 0,
      stdout = vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-workspace.txt"),
      stderr = {},
    })
    assert(text(bufnr):find("CVS commit history", 1, true), "directory opens commit-oriented history")
    assert(text(bufnr):find("commit ABC123", 1, true), "shared commit is rendered")
    assert(not text(bufnr):find("pkg/helper.lua", 1, true), "commit files begin collapsed")

    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "commit ABC123"), 0 })
    assert(service.toggle_preview(bufnr) == true, "equals expands a project commit")
    assert(text(bufnr):find("pkg/helper.lua", 1, true), "expanded commit lists every file")
    assert(service.copy_commit_id(bufnr) == "ABC123", "project history commit ID can be copied")

    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "pkg/helper.lua"), 0 })
    assert(log_buffer.current(bufnr).entry.path == "pkg/helper.lua", "expanded file can be selected")
  end)

  runner.run, capabilities.detect, util.notify = old_run, old_detect, old_notify
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.fn.delete(tmp, "rf")
  if not ok then error(err) end
end
