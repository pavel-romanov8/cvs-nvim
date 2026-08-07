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
