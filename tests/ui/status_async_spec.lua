local config = require("cvs.config")
local runner = require("cvs.cvs.runner")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

local function buffer_text(bufnr)
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
  local cvs_dir = temp_dir .. "/CVS"
  local fake_cvs = temp_dir .. "/fake-cvs"
  vim.fn.mkdir(cvs_dir, "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, cvs_dir .. "/Root")
  vim.fn.writefile({ "module" }, cvs_dir .. "/Repository")
  vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")

  config.setup({
    cvs = { bin = fake_cvs },
    notifications = { enabled = false },
  })

  local original_run = runner.run
  local pending
  runner.run = function(_, _, callback)
    pending = callback
    return { mocked = true }
  end

  local ok, err = pcall(function()
    local bufnr, winid = service.open({ path = temp_dir })
    assert_true(vim.api.nvim_buf_is_valid(bufnr), "async status opens its buffer immediately")
    assert_true(buffer_text(bufnr):find("Loading CVS status...", 1, true) ~= nil, "initial status shows loading")
    assert_true(type(pending) == "function", "status query remains pending")

    local stale = pending
    pending = nil
    state.invalidate_status_cache(temp_dir)
    stale({
      code = 0,
      stdout = { "M stale.lua" },
      stderr = {},
    })
    assert_true(type(pending) == "function", "cache invalidation retries an in-flight query")
    assert_true(buffer_text(bufnr):find("stale.lua", 1, true) == nil, "invalidated result is not rendered")

    local initial = pending
    pending = nil
    initial({
      code = 0,
      stdout = { "M changed.lua" },
      stderr = {},
    })
    assert_true(buffer_text(bufnr):find("M  changed.lua", 1, true) ~= nil, "async result updates status")
    assert_true(vim.api.nvim_get_current_line():find("M  changed.lua", 1, true) ~= nil, "initial result focuses its first file")

    pending = nil
    service.refresh(bufnr)
    assert_true(buffer_text(bufnr):find("(refreshing)", 1, true) ~= nil, "refresh retains content and shows progress")
    assert_true(type(pending) == "function", "refresh query remains pending")

    pending({
      code = 0,
      stdout = { "A added.lua" },
      stderr = {},
    })
    assert_true(buffer_text(bufnr):find("A  added.lua", 1, true) ~= nil, "refresh applies its async result")
    assert_true(buffer_text(bufnr):find("(refreshing)", 1, true) == nil, "refresh clears progress")

    pending = nil
    service.refresh(bufnr)
    pending({
      code = 1,
      signal = 0,
      stdout = { "A added.lua" },
      stderr = { 'cvs update: New directory "_bmad" -- ignored' },
    })
    assert_true(buffer_text(bufnr):find("A  added.lua", 1, true) ~= nil, "new-directory advisory preserves status")
    assert_true(
      buffer_text(bufnr):find("Status unavailable:", 1, true) == nil,
      "new-directory advisory is not a status failure"
    )

    pending = nil
    service.refresh(bufnr)
    pending({
      code = 124,
      signal = 15,
      stdout = { "M partial.lua" },
      stderr = {},
    })
    assert_true(buffer_text(bufnr):find("A  added.lua", 1, true) ~= nil, "failed refresh retains the complete snapshot")
    assert_true(buffer_text(bufnr):find("partial.lua", 1, true) == nil, "failed refresh does not render partial stdout")
    assert_true(buffer_text(bufnr):find("Status unavailable:", 1, true) ~= nil, "failed refresh displays its error")

    config.get().status.cache.enabled = false
    local callbacks = {}
    local completed = 0
    runner.run = function(_, _, callback)
      callbacks[#callbacks + 1] = callback
      return { mocked = true }
    end
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace }, function()
      completed = completed + 1
    end)
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace }, function()
      completed = completed + 1
    end)
    assert_true(#callbacks == 2, "disabled cache starts overlapping queries without superseding them")
    for _, callback in ipairs(callbacks) do
      callback({ code = 0, stdout = {}, stderr = {} })
    end
    assert_true(completed == 2, "disabled-cache queries both complete")

    local failed_snapshot
    local failed_error
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace }, function(snapshot, collect_err)
      failed_snapshot = snapshot
      failed_error = collect_err
    end)
    callbacks[#callbacks]({
      code = 124,
      signal = 15,
      stdout = { "M partial.lua" },
      stderr = {},
    })
    assert_true(failed_snapshot == nil, "failed status rejects partial stdout")
    assert_true(failed_error and failed_error.kind == "status_failed", "failed status reports a structured error")

    config.get().status.cache.enabled = true
    callbacks = {}
    local first_snapshot
    local first_error
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace, force = true }, function(snapshot, collect_err)
      first_snapshot = snapshot
      first_error = collect_err
    end)
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace, force = true }, function()
      error("callback failure")
    end)
    callbacks[1]({ code = 0, stdout = { "M superseded.lua" }, stderr = {} })
    assert_true(#callbacks == 2, "invalidated older query waits for the latest query")
    local callback_ok = pcall(callbacks[2], { code = 0, stdout = { "M current.lua" }, stderr = {} })
    assert_true(not callback_ok, "callback failures are still surfaced")
    assert_true(first_snapshot.files[1].path == "current.lua", "callback failure does not skip coalesced callers")
    assert_true(first_error == nil, "older query can still complete for its caller")
    local cached = state.get_status_cache(temp_dir, "workspace")
    assert_true(cached.snapshot.files[1].path == "current.lua", "latest forced query owns the cache")

    callbacks = {}
    local async_snapshot
    runner.run = function(_, _, callback)
      if callback then
        callbacks[#callbacks + 1] = callback
        return { mocked = true }
      end

      return { code = 0, signal = 0, stdout = { "M synchronous.lua" }, stderr = {} }
    end
    service.collect_async({ workspace = state.get_buffer(bufnr).view_state.workspace, force = true }, function(snapshot)
      async_snapshot = snapshot
    end)
    local synchronous = service.collect({ workspace = state.get_buffer(bufnr).view_state.workspace })
    callbacks[1]({ code = 0, stdout = { "M older-async.lua" }, stderr = {} })
    assert_true(synchronous.files[1].path == "synchronous.lua", "synchronous query returns its snapshot")
    assert_true(async_snapshot.files[1].path == "older-async.lua", "older async query still completes for its caller")
    cached = state.get_status_cache(temp_dir, "workspace")
    assert_true(cached.snapshot.files[1].path == "synchronous.lua", "newer synchronous query owns the cache")

    vim.api.nvim_win_close(winid, true)
  end)

  runner.run = original_run
  config.setup()
  state.buffers = {}
  state.workspaces = {}
  state.status_cache = {}
  state.status_cache_generation = {}
  vim.fn.delete(temp_dir, "rf")

  if not ok then
    error(err)
  end
end
