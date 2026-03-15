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
  if opts.path then
    local prefix = workspace.root_dir .. "/"
    if opts.path:sub(1, #prefix) == prefix then
      return opts.path:sub(#prefix + 1)
    end

    return opts.path
  end

  return "workspace"
end

local function refresh_status(opts)
  local ok, result = pcall(require("cvs.features.status.service").collect, opts)
  if ok then
    return result
  end

  return nil
end

local function build_view_state(workspace, opts)
  return {
    phase = "editing",
    workspace = workspace,
    scope_label = scope_label(workspace, opts),
    opts = vim.tbl_extend("force", {}, opts),
    message_lines = { "" },
    messages = {},
  }
end

function M.open(opts)
  opts = opts or {}

  local workspace, err = context.detect(opts.path)
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
      local ok, callback_err = pcall(function()
        local messages = vim.deepcopy(result.stdout)
        vim.list_extend(messages, result.stderr)

        view_state.phase = "done"
        view_state.result = result
        view_state.messages = messages
        view_state.completed_at = os.date("%Y-%m-%d %H:%M:%S")
        view_state.status_snapshot = refresh_status(view_state.opts)

        require("cvs.features.commit.buffer").update(bufnr, view_state)

        if result.code == 0 then
          events.emit("CvsChanged", {
            root_dir = view_state.workspace.root_dir,
            result = result,
            operation = "commit",
            scope = view_state.scope_label,
          })
          util.notify(("CVS commit completed for %s."):format(view_state.scope_label))
        else
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
    end)
  end, function(queue_err)
    util.notify(("CVS commit queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return command
end

M._build_view_state = build_view_state

return M
