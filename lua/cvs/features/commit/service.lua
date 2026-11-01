local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local config = require("cvs.config")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local util = require("cvs.core.util")

local uv = vim.uv or vim.loop

local M = {}

local function scope_label(workspace, opts)
  if opts.files and #opts.files > 0 then
    if #opts.files == 1 then
      return opts.files[1]
    end

    return ("%d selected files"):format(#opts.files)
  end

  if opts.path then
    local prefix = workspace.root_dir .. "/"
    if opts.path:sub(1, #prefix) == prefix then
      return opts.path:sub(#prefix + 1)
    end

    return opts.path
  end

  return "workspace"
end

local function refresh_status(workspace, opts, callback)
  local refresh_opts = vim.tbl_extend("force", {}, opts or {}, {
    force = true,
    workspace = workspace,
  })
  return require("cvs.features.status.service").collect_async(refresh_opts, function(result, err)
    callback(result, err)
  end)
end

local function build_view_state(workspace, opts)
  local command_opts = {}
  if opts.files and #opts.files > 0 then
    command_opts.files = vim.deepcopy(opts.files)
  elseif opts.path then
    command_opts.path = opts.path
  end

  return {
    phase = "editing",
    workspace = workspace,
    scope_label = scope_label(workspace, opts),
    opts = command_opts,
    files = vim.deepcopy(command_opts.files or {}),
    source_bufnr = opts.source_bufnr,
    source_win = opts.source_win,
    message_lines = vim.deepcopy(opts.message_lines or { "" }),
    messages = {},
  }
end

function M.open(opts)
  opts = opts or {}

  local workspace = opts.workspace
  local err
  if not workspace then
    workspace, err = context.detect(opts.path)
  end
  if not workspace then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local caps = capabilities.detect()
  if not caps.executable then
    err = errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local view_state = build_view_state(workspace, opts)
  local bufnr, winid = require("cvs.features.commit.buffer").open(view_state, opts)
  return bufnr, winid
end

local function refresh_source(view_state, callback)
  if view_state.source_bufnr and vim.api.nvim_buf_is_valid(view_state.source_bufnr) then
    return require("cvs.features.status.service").refresh(view_state.source_bufnr, nil, callback)
  end

  return refresh_status(view_state.workspace, view_state.opts, callback)
end

local function focus_source(view_state)
  local winid = view_state.source_win
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
    return
  end

  if view_state.source_bufnr and vim.api.nvim_buf_is_valid(view_state.source_bufnr) then
    local winids = vim.fn.win_findbuf(view_state.source_bufnr)
    if winids[1] and vim.api.nvim_win_is_valid(winids[1]) then
      vim.api.nvim_set_current_win(winids[1])
    end
  end
end

local function line_splitter(on_line)
  local partial = ""

  local function emit(line)
    on_line((line:gsub("\r$", "")))
  end

  return {
    push = function(data)
      local text = partial .. data
      local start = 1
      while true do
        local newline = text:find("\n", start, true)
        if not newline then
          break
        end
        emit(text:sub(start, newline - 1))
        start = newline + 1
      end
      partial = text:sub(start)
    end,
    flush = function()
      if partial ~= "" then
        emit(partial)
        partial = ""
      end
    end,
  }
end

local function start_timer(callback)
  local timer = uv.new_timer()
  if not timer then
    return nil
  end

  timer:start(1000, 1000, vim.schedule_wrap(callback))
  return timer
end

local function stop_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function completion_summary(view_state, result)
  local duration = util.format_duration(result.duration_ms)

  if result.code == 0 and not result.stream_error then
    return ("CVS commit succeeded for %s in %s. Press q to close."):format(view_state.scope_label, duration),
      vim.log.levels.INFO
  end

  local reason
  if result.stream_error then
    reason = "output error: " .. result.stream_error
  elseif result.code == 124 then
    reason = "timed out"
  elseif result.signal and result.signal ~= 0 then
    reason = ("killed by signal %d"):format(result.signal)
  else
    reason = ("exit code %d"):format(result.code)
  end

  return ("CVS commit FAILED for %s (%s) after %s. See the commit buffer for output."):format(
    view_state.scope_label,
    reason,
    duration
  ),
    vim.log.levels.ERROR
end

function M.close(bufnr)
  local attachment = state.get_buffer(bufnr)
  local view_state = attachment and attachment.view_state
  require("cvs.features.commit.buffer").close(bufnr)
  if view_state then
    focus_source(view_state)
  end
end

function M.submit(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "commit" then
    return nil, errors.new("commit_buffer_missing", "could not locate the CVS commit buffer state")
  end

  local view_state = attachment.view_state
  if view_state.phase == "queued" or view_state.phase == "running" then
    local err = errors.new("commit_in_progress", "a CVS commit is already in progress for this buffer")
    util.notify(errors.to_string(err), vim.log.levels.WARN)
    return nil, err
  end

  if view_state.phase == "done" and view_state.result and view_state.result.code == 0 then
    local err = errors.new("commit_completed", "this CVS commit already succeeded; press q to close the buffer")
    util.notify(errors.to_string(err), vim.log.levels.WARN)
    return nil, err
  end

  local commit_buffer = require("cvs.features.commit.buffer")
  local message_lines, message = commit_buffer.get_message(bufnr)
  if not message then
    local err = errors.new("commit_message_empty", "commit message cannot be empty")
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local command = cmd.commit(vim.tbl_extend("force", {}, view_state.opts or {}, {
    message = message,
  }))

  view_state.message_lines = message_lines
  view_state.command = command
  view_state.output = {}
  view_state.result = nil
  view_state.started_at = nil
  view_state.started_hrtime = nil
  view_state.completed_at = nil
  view_state.messages = {
    "Commit queued.",
  }
  view_state.phase = queue.is_busy(view_state.workspace.root_dir) and "queued" or "running"
  commit_buffer.update(bufnr, view_state)

  queue.enqueue(view_state.workspace.root_dir, function(done)
    local stdout_lines = {}
    local stderr_lines = {}
    local render_pending = false
    local timer

    local function render()
      render_pending = false
      if view_state.phase == "running" then
        commit_buffer.update(bufnr, view_state, { follow = true })
      end
    end

    local function schedule_render()
      if render_pending then
        return
      end
      render_pending = true
      vim.schedule(render)
    end

    local function collector(target)
      return line_splitter(function(line)
        target[#target + 1] = line
        view_state.output[#view_state.output + 1] = line
        schedule_render()
      end)
    end

    local stdout = collector(stdout_lines)
    local stderr = collector(stderr_lines)

    view_state.phase = "running"
    view_state.started_at = os.date("%Y-%m-%d %H:%M:%S")
    view_state.started_hrtime = uv.hrtime()
    view_state.messages = {}
    commit_buffer.update(bufnr, view_state, { follow = true })
    timer = start_timer(function()
      if view_state.phase ~= "running" or not vim.api.nvim_buf_is_valid(bufnr) then
        stop_timer(timer)
        return
      end
      commit_buffer.update(bufnr, view_state, { follow = true })
    end)

    local function on_complete(payload)
      stop_timer(timer)
      stdout.flush()
      stderr.flush()

      local result = vim.tbl_extend("force", {}, payload, {
        stdout = stdout_lines,
        stderr = stderr_lines,
      })
      if result.code == 0 and result.stream_error then
        result.code = 1
      end

      local function complete(status_snapshot, status_err)
        local ok, callback_err = pcall(function()
          local messages = {}
          if result.stream_error then
            messages[#messages + 1] = "Output error: " .. result.stream_error
          end
          if status_err then
            messages[#messages + 1] = "Status refresh failed: " .. errors.to_string(status_err)
          end

          view_state.phase = "done"
          view_state.result = result
          view_state.messages = messages
          view_state.completed_at = os.date("%Y-%m-%d %H:%M:%S")
          view_state.status_snapshot = status_snapshot

          if result.code == 0 then
            events.emit("CvsChanged", {
              root_dir = view_state.workspace.root_dir,
              result = result,
              operation = "commit",
              scope = view_state.scope_label,
              files = view_state.files,
            })
          end

          commit_buffer.update(bufnr, view_state, { follow = true })
          local summary, level = completion_summary(view_state, result)
          util.notify(summary, level)
        end)

        if not ok then
          view_state.phase = "done"
          view_state.completed_at = os.date("%Y-%m-%d %H:%M:%S")
          view_state.messages = { ("Internal error: %s"):format(callback_err) }
          commit_buffer.update(bufnr, view_state, { follow = true })
          util.notify(("CVS commit failed internally: %s"):format(callback_err), vim.log.levels.ERROR)
        end

        done()
      end

      local ok, refresh_err = pcall(refresh_source, view_state, complete)
      if not ok then
        util.notify(("CVS status refresh failed internally: %s"):format(refresh_err), vim.log.levels.ERROR)
        complete(nil, refresh_err)
      end
    end

    local process_ok, process_err = pcall(runner.stream, command, {
      cwd = view_state.workspace.root_dir,
      timeout = config.get().cvs.commit_timeout_ms or false,
    }, {
      on_stdout = stdout.push,
      on_stderr = stderr.push,
      on_complete = on_complete,
    })
    if not process_ok then
      on_complete({
        cmd = command,
        code = 1,
        stream_error = tostring(process_err),
        duration_ms = 0,
      })
    end
  end, function(queue_err)
    util.notify(("CVS commit queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return command
end

M._line_splitter = line_splitter

M._build_view_state = build_view_state

return M
