local service = require("cvs.features.log.service")
local runner = require("cvs.cvs.runner")
local capabilities = require("cvs.cvs.capabilities")
local log_buffer = require("cvs.features.log.buffer")
local util = require("cvs.core.util")

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
    calls[#calls + 1] = { command = command, opts = opts, callback = callback }
    return { kill = function() end }
  end

  local ok, err = pcall(function()
    local missing, validation = service.open({ path = tmp })
    assert(missing == nil and validation.kind == "log_requires_file", "directories are rejected")
    local bufnr, winid = service.open({ path = tmp .. "/file.lua", kind = "split" })
    assert(vim.api.nvim_buf_is_valid(bufnr), "log opens immediately")
    assert(vim.api.nvim_buf_get_lines(bufnr, 3, 4, false)[1] == "Loading CVS log...", "loading state")
    assert(calls[1].opts.cwd == tmp and calls[1].command[#calls[1].command] == "file.lua", "file-local command")
    calls[1].callback({ code = 0, signal = 0, stdout = vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-basic.txt"), stderr = {} })
    local entry_row
    for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:match("^revision 1%.2 ") then entry_row = row end
    end
    assert(entry_row, "revisions rendered")
    vim.api.nvim_win_set_cursor(winid, { entry_row, 0 })
    assert(log_buffer.current(bufnr).revision == "1.2", "cursor identifies revision")
    service.open_revision(bufnr)
    assert(table.concat(calls[2].command, " "):match("update %-p %-r 1%.2 file%.lua$"), "revision fetched without changing working file")
    calls[2].callback({ code = 0, signal = 0, stdout = { "local x = 0" }, stderr = {} })
    local revision_buf = vim.api.nvim_get_current_buf()
    assert(vim.bo[revision_buf].readonly and not vim.bo[revision_buf].modifiable, "revision is read-only")
    assert(vim.fn.readfile(tmp .. "/file.lua")[1] == "local x = 1", "working file untouched")
    vim.api.nvim_set_current_win(winid)
    service.diff_revision(bufnr)
    assert(table.concat(calls[3].command, " "):match("diff %-u %-r 1%.1 %-r 1%.2 file%.lua$"), "revision diff arguments")
    calls[3].callback({ code = 1, signal = 0, stdout = { "--- old", "+++ new" }, stderr = {} })
    assert(vim.bo[vim.api.nvim_get_current_buf()].filetype == "diff", "diff exit code 1 shows diff")
    vim.api.nvim_set_current_win(winid)
    service.refresh(bufnr)
    assert(#calls == 4, "refresh reruns CVS log")
    calls[4].callback({ code = 0, signal = 0, stdout = vim.fn.readfile(root .. "/tests/fixtures/cvs/log/sample-basic.txt"), stderr = {} })
    assert(log_buffer.current(bufnr).revision == "1.2", "refresh restores selected revision")
    local has_toggle = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if mapping.lhs == "=" then has_toggle = true end
    end
    assert(has_toggle, "= is mapped in the log buffer")
    assert(service.toggle_preview(bufnr) == true, "preview opens")
    assert(vim.api.nvim_get_current_buf() == bufnr, "preview stays in history buffer")
    assert(table.concat(calls[5].command, " "):match("update %-p %-r 1%.2 file%.lua$"), "preview fetches selected revision")
    assert(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("Loading revision contents...", 1, true), "loading preview visible")
    local contents = {}
    for i = 1, 205 do contents[i] = "source line " .. i end
    calls[5].callback({ code = 0, signal = 0, stdout = contents, stderr = {} })
    local rendered = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    assert(rendered:find("| source line 200", 1, true), "revision content rendered inline")
    assert(not rendered:find("| source line 201", 1, true), "inline preview is bounded")
    assert(rendered:find("preview truncated", 1, true), "truncation indicated")
    local content_row
    for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:find("| source line 1", 1, true) then content_row = row break end
    end
    vim.api.nvim_win_set_cursor(winid, { content_row, 0 })
    assert(log_buffer.current(bufnr).revision == "1.2", "preview lines target their revision")
    assert(service.toggle_preview(bufnr) == false, "same revision collapses")
    assert(not table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("source line 1", 1, true), "preview removed")

    service.toggle_preview(bufnr)
    assert(#calls == 6, "reopening loads preview")
    local head_row
    for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:match("^revision 1%.3 ") then head_row = row break end
    end
    vim.api.nvim_win_set_cursor(winid, { head_row, 0 })
    service.toggle_preview(bufnr)
    assert(#calls == 7, "selecting another revision replaces preview")
    calls[6].callback({ code = 0, signal = 0, stdout = { "stale source" }, stderr = {} })
    assert(not table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("stale source", 1, true), "stale preview ignored")
    calls[7].callback({ code = 1, signal = 0, stdout = {}, stderr = { "revision unavailable" } })
    assert(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("Could not load revision: revision unavailable", 1, true), "preview errors shown inline")

    service.refresh(bufnr)
    assert(#calls == 8, "refresh reruns log")
    assert(not table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("revision unavailable", 1, true), "refresh clears preview")
    service.refresh(bufnr)
    calls[8].callback({ code = 1, signal = 0, stdout = {}, stderr = { "old error" } })
    assert(vim.api.nvim_buf_get_lines(bufnr, 3, 4, false)[1] == "Loading CVS log...", "stale response ignored")
    calls[9].callback({ code = 1, signal = 0, stdout = {}, stderr = { "cvs log: failed" } })
    assert(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find("CVS log failed: cvs log: failed", 1, true), "errors shown in log buffer")
  end)

  runner.run, capabilities.detect, util.notify = old_run, old_detect, old_notify
  vim.cmd("tabonly!")
  vim.cmd("only!")
  vim.fn.delete(tmp, "rf")
  if not ok then error(err) end
end
