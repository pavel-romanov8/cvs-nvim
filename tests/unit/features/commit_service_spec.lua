local commit_buffer = require("cvs.features.commit.buffer")
local capabilities = require("cvs.cvs.capabilities")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local service = require("cvs.features.commit.service")
local state = require("cvs.core.state")
local status_service = require("cvs.features.status.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local original_get_message = commit_buffer.get_message
  local original_open = commit_buffer.open
  local original_update = commit_buffer.update
  local original_update_validation = commit_buffer.update_validation
  local original_close = commit_buffer.close
  local original_detect = capabilities.detect
  local original_emit = events.emit
  local original_is_busy = queue.is_busy
  local original_enqueue = queue.enqueue
  local original_run = runner.run
  local original_refresh = status_service.refresh
  local original_collect_async = status_service.collect_async
  local buffers = {}

  local ok, err = pcall(function()
    require("cvs.config").setup({
      notifications = { enabled = false },
    })

    local workspace = { root_dir = "/tmp/work" }
    local source_bufnr = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = source_bufnr
    local source_win = vim.api.nvim_get_current_win()
    local built = service._build_view_state(workspace, {
      workspace = workspace,
      path = workspace.root_dir,
      files = { "pkg/one.lua", "pkg/two.lua" },
      source_bufnr = source_bufnr,
      source_win = source_win,
    })
    assert_eq(built.scope_label, "2 selected files", "selected-file scope label")
    assert_eq(built.opts.workspace, nil, "workspace is not a command target")
    assert_eq(built.opts.path, nil, "selected files take precedence over path scope")
    assert_eq(#built.opts.files, 2, "command options retain selected files")
    assert_eq(built.validation.status, "checking", "commit starts with validation pending")

    local valid = service._validate_snapshot({
      files = {
        { path = "pkg/one.lua", status = "modified" },
        { path = "pkg/two.lua", status = "added" },
      },
      result = { code = 0, stdout = {}, stderr = {} },
    }, built.files)
    assert_eq(valid.status, "ready", "selected committable files pass validation")

    local invalid = service._validate_snapshot({
      files = {
        { path = "pkg/one.lua", status = "modified" },
      },
      result = { code = 0, stdout = {}, stderr = {} },
    }, built.files)
    assert_eq(invalid.status, "blocked", "missing selected files block validation")

    local pending_callback
    capabilities.detect = function()
      return { bin = "cvs", executable = true }
    end
    commit_buffer.open = function(view_state)
      local bufnr = vim.api.nvim_create_buf(false, true)
      buffers[#buffers + 1] = bufnr
      state.attach_buffer(bufnr, {
        kind = "commit",
        root_dir = workspace.root_dir,
        view_state = view_state,
      })
      return bufnr, 321
    end
    commit_buffer.update_validation = function() end
    status_service.collect_async = function(_, callback)
      pending_callback = callback
      return { mocked = true }
    end
    local opened_bufnr, opened_win = service.open({
      workspace = workspace,
      files = { "pkg/one.lua" },
    })
    assert_eq(opened_win, 321, "commit editor opens before validation completes")
    assert_eq(type(pending_callback), "function", "commit validation runs in the background")
    assert_eq(state.get_buffer(opened_bufnr).view_state.validation.status, "checking", "open editor is pending")
    pending_callback({
      files = { { path = "pkg/one.lua", status = "modified" } },
      result = { code = 0, stdout = {}, stderr = {} },
    })
    assert_eq(state.get_buffer(opened_bufnr).view_state.validation.status, "ready", "background validation enables commit")
    capabilities.detect = original_detect
    commit_buffer.open = original_open
    commit_buffer.update_validation = original_update_validation
    status_service.collect_async = original_collect_async

    local result = { code = 0, stdout = { "committed" }, stderr = {} }
    local command
    local refreshed_bufnr
    local closed_bufnr
    local emitted
    local last_update

    commit_buffer.get_message = function()
      return { "Commit subject" }, "Commit subject"
    end
    commit_buffer.update = function(_, view_state)
      last_update = vim.deepcopy(view_state)
    end
    commit_buffer.close = function(bufnr)
      closed_bufnr = bufnr
    end
    events.emit = function(name, data)
      emitted = { name = name, data = data }
    end
    queue.is_busy = function()
      return false
    end
    queue.enqueue = function(_, work)
      work(function() end)
    end
    runner.run = function(next_command, _, callback)
      command = next_command
      callback(result)
    end
    status_service.refresh = function(bufnr, _, callback)
      refreshed_bufnr = bufnr
      callback({ files = {} })
    end

    local commit_bufnr = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = commit_bufnr
    state.attach_buffer(commit_bufnr, {
      kind = "commit",
      root_dir = workspace.root_dir,
      view_state = built,
    })

    local _, pending_err = service.submit(commit_bufnr)
    assert_eq(pending_err.kind, "commit_validation_checking", "pending validation blocks submission")
    assert_eq(command, nil, "pending validation does not run CVS commit")
    built.validation = { status = "ready", message = "ready" }
    service.submit(commit_bufnr)
    assert_eq(
      table.concat(command, " "),
      "cvs commit -m Commit subject pkg/one.lua pkg/two.lua",
      "commit uses only selected files"
    )
    assert_eq(refreshed_bufnr, source_bufnr, "successful commit refreshes source status")
    assert_eq(closed_bufnr, commit_bufnr, "successful selected commit closes its editor")
    assert_eq(emitted.name, "CvsChanged", "successful commit emits changed event")
    assert_eq(#emitted.data.files, 2, "commit event includes selected files")

    result = { code = 1, stdout = {}, stderr = { "commit failed" } }
    refreshed_bufnr = nil
    closed_bufnr = nil
    last_update = nil
    local failed_bufnr = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = failed_bufnr
    local failed_state = service._build_view_state(workspace, {
      workspace = workspace,
      files = { "pkg/one.lua" },
      source_bufnr = source_bufnr,
      source_win = source_win,
    })
    failed_state.validation = { status = "ready", message = "ready" }
    state.attach_buffer(failed_bufnr, {
      kind = "commit",
      root_dir = workspace.root_dir,
      view_state = failed_state,
    })

    service.submit(failed_bufnr)
    assert_eq(refreshed_bufnr, source_bufnr, "failed commit reconciles source status")
    assert_eq(closed_bufnr, nil, "failed commit keeps its editor open")
    assert_eq(last_update.phase, "done", "failed commit renders its completed state")
    assert_eq(last_update.message_lines[1], "Commit subject", "failed commit preserves its message")
    assert_eq(last_update.messages[1], "commit failed", "failed commit displays the CVS error")
  end)

  commit_buffer.get_message = original_get_message
  commit_buffer.open = original_open
  commit_buffer.update = original_update
  commit_buffer.update_validation = original_update_validation
  commit_buffer.close = original_close
  capabilities.detect = original_detect
  events.emit = original_emit
  queue.is_busy = original_is_busy
  queue.enqueue = original_enqueue
  runner.run = original_run
  status_service.refresh = original_refresh
  status_service.collect_async = original_collect_async
  for _, bufnr in ipairs(buffers) do
    state.detach_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  if not ok then
    error(err)
  end
end
