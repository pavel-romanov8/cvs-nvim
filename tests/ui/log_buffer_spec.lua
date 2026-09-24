local service = require("cvs.features.log.service")
local runner = require("cvs.cvs.runner")
local capabilities = require("cvs.cvs.capabilities")
local log_buffer = require("cvs.features.log.buffer")
local util = require("cvs.core.util")

local function text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function row_for(bufnr, pattern)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find(pattern, 1, true) then return row end
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
  local change = { "Index: file.lua", "--- file.lua", "+++ file.lua", "@@ -1 +1 @@", "-local old = 1", "+local new = 2" }

  local ok, err = pcall(function()
    local missing, validation = service.open({ path = tmp })
    assert(missing == nil and validation.kind == "log_requires_file", "directories are rejected")
    local source_height = vim.api.nvim_win_get_height(0)
    local window_count = #vim.api.nvim_tabpage_list_wins(0)
    local bufnr, winid = service.open({ path = tmp .. "/file.lua" })
    assert(#vim.api.nvim_tabpage_list_wins(0) == window_count + 1, "log defaults to a horizontal split")
    assert(vim.api.nvim_win_get_height(winid) <= math.floor(source_height * 0.5) + 1,
      "log defaults to half the source window height")
    assert(text(bufnr):find("Loading CVS log...", 1, true), "log opens with loading state")
    assert(calls[1].opts.cwd == tmp and calls[1].command[#calls[1].command] == "file.lua", "file-local log")
    calls[1].callback({ code = 0, signal = 0, stdout = fixture, stderr = {} })
    local entry_row = row_for(bufnr, "revision 1.2 ")
    assert(entry_row, "revisions rendered")
    vim.api.nvim_win_set_cursor(winid, { entry_row, 0 })
    assert(log_buffer.current(bufnr).revision == "1.2", "cursor identifies revision")

    local full_buf = service.open_revision(bufnr)
    assert(vim.api.nvim_get_current_buf() == full_buf, "full diff split opens immediately")
    assert(text(full_buf):find("Loading revision diff...", 1, true), "full diff shows loading before CVS finishes")
    assert(table.concat(calls[2].command, " "):match("diff %-u %-r 1%.1 %-r 1%.2 file%.lua$"), "full view diffs predecessor")
    calls[2].callback({ code = 1, signal = 0, stdout = change, stderr = {} })
    assert(vim.bo[full_buf].filetype == "diff" and vim.bo[full_buf].syntax == "diff", "diff syntax enabled")
    assert(vim.bo[full_buf].readonly and not vim.bo[full_buf].modifiable, "full diff is read-only")
    assert(text(full_buf):find("@@ -1 +1 @@", 1, true) and text(full_buf):find("+local new = 2", 1, true), "full view shows changed hunks")
    assert(not text(full_buf):find("Index: file.lua", 1, true), "CVS preamble hidden")
    local has_lua_parser = pcall(vim.treesitter.get_string_parser, "local x = 1", "lua")
      and vim.treesitter.query.get("lua", "highlights") ~= nil
    if has_lua_parser then
      local full_ns = vim.api.nvim_create_namespace("cvs-log-full-syntax")
      assert(vim.wait(500, function()
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(full_buf, full_ns, 0, -1, { details = true })) do
          if mark[4].hl_group == "CvsLogSyntaxkeyword_lua" then return true end
        end
      end), "full diff receives source-language syntax highlights")
    end
    assert(vim.fn.readfile(tmp .. "/file.lua")[1] == "local x = 1", "working file untouched")

    vim.api.nvim_set_current_win(winid)
    service.toggle_preview(bufnr)
    assert(vim.api.nvim_get_current_buf() == bufnr, "inline diff stays in log")
    assert(text(bufnr):find("Loading revision diff...", 1, true), "inline loading state")
    assert(table.concat(calls[3].command, " "):match("diff %-u %-r 1%.1 %-r 1%.2 file%.lua$"), "inline compares revisions")
    calls[3].callback({ code = 1, signal = 0, stdout = change, stderr = {} })
    assert(text(bufnr):find("| @@ -1 +1 @@", 1, true) and text(bufnr):find("| +local new = 2", 1, true), "inline shows diff, not full file")
    local highlights = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("cvs-log"), 0, -1, { details = true })
    local seen = {}
    for _, mark in ipairs(highlights) do
      seen[mark[4].hl_group] = true
    end
    assert(seen.CvsDiffAdd and seen.CvsDiffDelete and seen.CvsDiffChange,
      "inline diff additions, removals, hunks highlighted")
    if has_lua_parser then
      assert(vim.wait(500, function()
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("cvs-log"), 0, -1, { details = true })) do
          if mark[4].hl_group == "CvsLogSyntaxkeyword_lua" and mark[3] == 7 then return true end
        end
      end), "inline diff receives source-language syntax past UI and diff prefixes")
    end
    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "| +local new = 2"), 0 })
    assert(log_buffer.current(bufnr).revision == "1.2", "inline lines select their revision")
    assert(service.toggle_preview(bufnr) == false, "same revision collapses")
    assert(not text(bufnr):find("| +local new = 2", 1, true), "inline diff removed")

    service.toggle_preview(bufnr)
    local many = { "@@ -0,0 +1,205 @@" }
    for i = 1, 205 do many[#many + 1] = "+source line " .. i end
    calls[4].callback({ code = 1, signal = 0, stdout = many, stderr = {} })
    assert(text(bufnr):find("| +source line 199", 1, true), "inline shows bounded hunks")
    assert(not text(bufnr):find("| +source line 200", 1, true), "preview stops at configured limit")
    assert(text(bufnr):find("diff truncated", 1, true), "truncation disclosed")

    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "revision 1.3 "), 0 })
    service.toggle_preview(bufnr)
    calls[5].callback({ code = 1, signal = 0, stdout = {}, stderr = { "revision unavailable" } })
    assert(text(bufnr):find("Could not load diff: revision unavailable", 1, true), "inline errors visible")
    service.refresh(bufnr)
    assert(not text(bufnr):find("revision unavailable", 1, true), "refresh clears preview")
    calls[6].callback({ code = 0, signal = 0, stdout = fixture, stderr = {} })
    assert(log_buffer.current(bufnr).revision == "1.3", "refresh preserves selected revision")

    vim.api.nvim_win_set_cursor(winid, { row_for(bufnr, "revision 1.1 "), 0 })
    local first_buf = service.open_revision(bufnr)
    assert(table.concat(calls[7].command, " "):match("update %-p %-r 1%.1 file%.lua$"), "initial revision compared to empty base")
    calls[7].callback({ code = 0, signal = 0, stdout = { "initial line" }, stdout_ends_with_newline = true, stderr = {} })
    assert(text(first_buf):find("+initial line", 1, true), "initial revision shows addition diff")

    vim.api.nvim_set_current_win(winid)
    local abandoned = service.open_revision(bufnr)
    vim.api.nvim_buf_delete(abandoned, { force = true })
    assert(calls[8].killed, "closing a loading full diff cancels CVS")
    calls[8].callback({ code = 1, signal = 0, stdout = change, stderr = {} })
    service.refresh(bufnr)
    service.refresh(bufnr)
    calls[9].callback({ code = 1, signal = 0, stdout = {}, stderr = { "old error" } })
    assert(text(bufnr):find("Loading CVS log...", 1, true), "stale response ignored")
    calls[10].callback({ code = 1, signal = 0, stdout = {}, stderr = { "cvs log: failed" } })
    assert(text(bufnr):find("CVS log failed: cvs log: failed", 1, true), "errors shown in log")
  end)

  runner.run, capabilities.detect, util.notify = old_run, old_detect, old_notify
  vim.cmd("tabonly!")
  vim.cmd("only!")
  vim.fn.delete(tmp, "rf")
  if not ok then error(err) end
end
