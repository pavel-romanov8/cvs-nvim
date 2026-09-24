local config = require("cvs.config")
local runner = require("cvs.cvs.runner")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")

local function text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  state.buffers = {}
  state.workspaces = {}
  state.status_cache = {}
  state.status_cache_generation = {}

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir .. "/CVS", "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, temp_dir .. "/CVS/Root")
  vim.fn.writefile({ "module" }, temp_dir .. "/CVS/Repository")
  local fake_cvs = temp_dir .. "/fake-cvs"
  vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")
  config.setup({ cvs = { bin = fake_cvs }, notifications = { enabled = false } })

  local original_run = runner.run
  local pending
  runner.run = function(_, _, callback)
    pending = callback
    return { mocked = true }
  end

  local bufnr
  local ok, err = pcall(function()
    local winid
    bufnr, winid = service.open({ path = temp_dir })
    assert(text(bufnr):find("Loading CVS status", 1, true) and type(pending) == "function",
      "status opens before its CVS query completes")

    local stale = pending
    pending = nil
    state.invalidate_status_cache(temp_dir)
    stale({ code = 0, signal = 0, stdout = { "M stale.lua" }, stderr = {} })
    assert(type(pending) == "function" and not text(bufnr):find("stale.lua", 1, true),
      "cache invalidation retries rather than rendering stale output")
    pending({ code = 0, signal = 0, stdout = { "M changed.lua" }, stderr = {} })
    assert(text(bufnr):find("M  changed.lua", 1, true), "async output updates the status buffer")

    pending = nil
    service.refresh(bufnr)
    assert(text(bufnr):find("changed.lua", 1, true) and text(bufnr):find("refreshing", 1, true),
      "refresh keeps the last useful snapshot visible")
    pending({ code = 1, signal = 0, stdout = { "M partial.lua" }, stderr = {
      'cvs update: cannot open directory "old/one": No such file or directory',
    } })
    assert(text(bufnr):find("M  partial.lua", 1, true)
      and text(bufnr):find("Status incomplete: CVS exited with code 1", 1, true),
      "parseable partial output is retained with an explicit warning")

    pending = nil
    service.refresh(bufnr)
    pending({ code = 124, signal = 15, stdout = { "M unsafe.lua" }, stderr = {} })
    assert(text(bufnr):find("M  partial.lua", 1, true) and not text(bufnr):find("unsafe.lua", 1, true),
      "hard refresh failure retains the previous snapshot")
    assert(text(bufnr):find("Status unavailable", 1, true) and text(bufnr):find("timed out", 1, true),
      "hard failure remains visible and actionable")

    local callbacks = {}
    runner.run = function(_, _, callback)
      callbacks[#callbacks + 1] = callback
      return { mocked = true }
    end
    local first_snapshot
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace, force = true }, function(snapshot)
      first_snapshot = snapshot
    end)
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace, force = true }, function() end)
    callbacks[1]({ code = 0, signal = 0, stdout = { "M superseded.lua" }, stderr = {} })
    assert(#callbacks == 2, "overlapping forced reads coalesce behind the latest query")
    callbacks[2]({ code = 0, signal = 0, stdout = { "M current.lua" }, stderr = {} })
    local cached = state.get_status_cache(temp_dir, "workspace")
    assert(first_snapshot.files[1].path == "current.lua"
      and cached.snapshot.files[1].path == "current.lua", "latest forced result serves callers and owns the cache")

    vim.api.nvim_win_close(winid, true)
  end)

  runner.run = original_run
  config.setup()
  state.buffers = {}
  state.workspaces = {}
  state.status_cache = {}
  state.status_cache_generation = {}
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
  vim.fn.delete(temp_dir, "rf")
  if not ok then error(err) end
end
