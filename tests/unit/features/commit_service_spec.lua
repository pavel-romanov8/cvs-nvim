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
  local original_close = commit_buffer.close
  local original_detect = capabilities.detect
  local original_emit = events.emit
  local original_is_busy = queue.is_busy
  local original_enqueue = queue.enqueue
  local original_stream = runner.stream
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
    local prefilled = service._build_view_state(workspace, {
      workspace = workspace,
      files = { "pkg/one.lua" },
      message_lines = { "Revert change", "", "Reverts CVS commit ABC123." },
    })
    assert_eq(prefilled.message_lines[1], "Revert change", "commit editor accepts a generated message")

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
    local opened_bufnr, opened_win = service.open({
      workspace = workspace,
      files = { "pkg/one.lua" },
    })
    assert_eq(opened_win, 321, "commit editor opens")
    assert_eq(state.get_buffer(opened_bufnr).view_state.validation, nil, "commit does not prevalidate CVS state")
    capabilities.detect = original_detect
    commit_buffer.open = original_open

    local chunks = {
      { "stdout", "Checking in pkg/one.lua;\nnew revision: 1.2; prev" },
      { "stderr", "check: lint ok\r\n" },
      { "stdout", "ious revision: 1.1\ndone" },
    }
    local result = { code = 0 }
    local command
    local stream_opts
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
    runner.stream = function(next_command, opts, handlers)
      command = next_command
      stream_opts = opts
      for _, chunk in ipairs(chunks) do
        if chunk[1] == "stdout" then
          handlers.on_stdout(chunk[2])
        else
          handlers.on_stderr(chunk[2])
        end
      end
      handlers.on_complete(vim.tbl_extend("force", { duration_ms = 75000 }, result))
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

    service.submit(commit_bufnr)
    assert_eq(
      table.concat(command, " "),
      "cvs commit -m Commit subject pkg/one.lua pkg/two.lua",
      "commit uses only selected files"
    )
    assert_eq(stream_opts.timeout, false, "commit is not bounded by the generic command timeout")
    assert_eq(refreshed_bufnr, source_bufnr, "successful commit refreshes source status")
    assert_eq(closed_bufnr, nil, "successful commit keeps its output visible")
    assert_eq(last_update.phase, "done", "successful commit renders its completed state")
    assert_eq(last_update.result.code, 0, "successful commit records its result")
    assert_eq(
      table.concat(last_update.output, "|"),
      "Checking in pkg/one.lua;|check: lint ok|new revision: 1.2; previous revision: 1.1|done",
      "chunked stdout and stderr are reassembled into complete lines"
    )
    assert_eq(emitted.name, "CvsChanged", "successful commit emits changed event")
    assert_eq(#emitted.data.files, 2, "commit event includes selected files")

    local _, resubmit_err = service.submit(commit_bufnr)
    assert_eq(resubmit_err and resubmit_err.kind, "commit_completed", "a succeeded commit cannot be resubmitted")

    chunks = { { "stderr", "commit failed\n" } }
    result = { code = 1 }
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
    assert_eq(last_update.output[1], "commit failed", "failed commit displays the CVS error")
  end)

  commit_buffer.get_message = original_get_message
  commit_buffer.open = original_open
  commit_buffer.update = original_update
  commit_buffer.close = original_close
  capabilities.detect = original_detect
  events.emit = original_emit
  queue.is_busy = original_is_busy
  queue.enqueue = original_enqueue
  runner.stream = original_stream
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
