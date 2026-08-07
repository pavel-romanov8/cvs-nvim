local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local util = require("cvs.core.util")

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
  return require("cvs.features.status.service").collect_async(refresh_opts, function(result)
    callback(result)
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
    message_lines = { "" },
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

  return require("cvs.features.commit.buffer").open(build_view_state(workspace, opts), opts)
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

function M.submit(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "commit" then
    return nil, errors.new("commit_buffer_missing", "could not locate the CVS commit buffer state")
  end

  local view_state = attachment.view_state
  if view_state.phase == "queued" or view_state.phase == "running" then
    return nil, errors.new("commit_in_progress", "a CVS commit is already in progress for this buffer")
  end

  local message_lines, message = require("cvs.features.commit.buffer").get_message(bufnr)
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
  view_state.messages = {
    "Commit queued.",
  }
  view_state.phase = queue.is_busy(view_state.workspace.root_dir) and "queued" or "running"
  require("cvs.features.commit.buffer").update(bufnr, view_state)

  queue.enqueue(view_state.workspace.root_dir, function(done)
    view_state.phase = "running"
    view_state.started_at = os.date("%Y-%m-%d %H:%M:%S")
    view_state.messages = {
      "Running CVS commit...",
    }
    require("cvs.features.commit.buffer").update(bufnr, view_state)

    runner.run(command, {
      cwd = view_state.workspace.root_dir,
    }, function(result)
      local function complete(status_snapshot)
        local ok, callback_err = pcall(function()
          local messages = vim.deepcopy(result.stdout)
          vim.list_extend(messages, result.stderr)

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
            util.notify(("CVS commit completed for %s."):format(view_state.scope_label))

            if view_state.source_bufnr then
              require("cvs.features.commit.buffer").close(bufnr)
              focus_source(view_state)
            else
              require("cvs.features.commit.buffer").update(bufnr, view_state)
            end
          else
            require("cvs.features.commit.buffer").update(bufnr, view_state)
            local message_text = messages[1] or ("CVS commit exited with code %d."):format(result.code)
            util.notify(message_text, vim.log.levels.WARN)
          end
        end)

        if not ok then
          view_state.phase = "done"
          view_state.completed_at = os.date("%Y-%m-%d %H:%M:%S")
          view_state.messages = { ("Internal error: %s"):format(callback_err) }
          require("cvs.features.commit.buffer").update(bufnr, view_state)
          util.notify(("CVS commit failed internally: %s"):format(callback_err), vim.log.levels.ERROR)
        end

        done()
      end

      local ok, refresh_err = pcall(refresh_source, view_state, complete)
      if not ok then
        util.notify(("CVS status refresh failed internally: %s"):format(refresh_err), vim.log.levels.ERROR)
        complete(nil)
      end
    end)
  end, function(queue_err)
    util.notify(("CVS commit queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return command
end

M._build_view_state = build_view_state

return M
