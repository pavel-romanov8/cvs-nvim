local commit_buffer = require("cvs.features.commit.buffer")
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
  local original_update = commit_buffer.update
  local original_close = commit_buffer.close
  local original_emit = events.emit
  local original_is_busy = queue.is_busy
  local original_enqueue = queue.enqueue
  local original_run = runner.run
  local original_refresh = status_service.refresh
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
    status_service.refresh = function(bufnr)
      refreshed_bufnr = bufnr
      return { files = {} }
    end

    local commit_bufnr = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = commit_bufnr
    state.attach_buffer(commit_bufnr, {
      kind = "commit",
      root_dir = workspace.root_dir,
      view_state = built,
    })

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
    state.attach_buffer(failed_bufnr, {
      kind = "commit",
      root_dir = workspace.root_dir,
      view_state = service._build_view_state(workspace, {
        workspace = workspace,
        files = { "pkg/one.lua" },
        source_bufnr = source_bufnr,
        source_win = source_win,
      }),
    })

    service.submit(failed_bufnr)
    assert_eq(refreshed_bufnr, source_bufnr, "failed commit reconciles source status")
    assert_eq(closed_bufnr, nil, "failed commit keeps its editor open")
    assert_eq(last_update.phase, "done", "failed commit renders its completed state")
    assert_eq(last_update.message_lines[1], "Commit subject", "failed commit preserves its message")
    assert_eq(last_update.messages[1], "commit failed", "failed commit displays the CVS error")
  end)

  commit_buffer.get_message = original_get_message
  commit_buffer.update = original_update
  commit_buffer.close = original_close
  events.emit = original_emit
  queue.is_busy = original_is_busy
  queue.enqueue = original_enqueue
  runner.run = original_run
  status_service.refresh = original_refresh
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
