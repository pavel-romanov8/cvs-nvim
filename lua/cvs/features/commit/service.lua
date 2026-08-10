local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local types = require("cvs.core.types")
local util = require("cvs.core.util")

local M = {}
local committable_statuses = {
  [types.status.modified] = true,
  [types.status.added] = true,
  [types.status.removed] = true,
}

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
    message_lines = { "" },
    messages = {},
    validation = {
      status = "checking",
      message = "checking CVS state...",
    },
  }
end

local function validation_failure(snapshot, err)
  if err then
    return errors.to_string(err)
  end

  local result = snapshot and snapshot.result
  if result and result.code ~= 0 then
    return result.stderr[1] or result.stdout[1] or ("CVS status exited with code %d."):format(result.code)
  end

  return nil
end

local function validate_snapshot(snapshot, files, err)
  local failure = validation_failure(snapshot, err)
  if failure then
    return {
      status = "blocked",
      message = "blocked - " .. failure,
    }
  end

  local statuses = {}
  local committable_count = 0
  local has_conflict = false
  for _, file in ipairs(snapshot and snapshot.files or {}) do
    statuses[file.path] = file.status
    if committable_statuses[file.status] then
      committable_count = committable_count + 1
    elseif file.status == types.status.conflict then
      has_conflict = true
    end
  end

  if files and #files > 0 then
    local invalid = {}
    for _, path in ipairs(files) do
      if not committable_statuses[statuses[path]] then
        invalid[#invalid + 1] = path
      end
    end
    if #invalid > 0 then
      return {
        status = "blocked",
        message = "blocked - no longer committable: " .. table.concat(invalid, ", "),
      }
    end
  elseif has_conflict then
    return {
      status = "blocked",
      message = "blocked - resolve CVS conflicts before committing",
    }
  elseif committable_count == 0 then
    return {
      status = "blocked",
      message = "blocked - no committable changes found",
    }
  end

  return {
    status = "ready",
    message = "ready",
  }
end

local function set_validation(bufnr, view_state, validation)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "commit" or attachment.view_state ~= view_state then
    return
  end

  view_state.validation = validation
  require("cvs.features.commit.buffer").update_validation(bufnr, validation)
end

local function validate_async(bufnr, view_state)
  local validation_opts = {
    force = true,
    workspace = view_state.workspace,
  }
  if #view_state.files == 0 and view_state.opts.path then
    validation_opts.path = view_state.opts.path
  end

  local ok, validation_err = pcall(function()
    require("cvs.features.status.service").collect_async(validation_opts, function(snapshot, err)
      set_validation(bufnr, view_state, validate_snapshot(snapshot, view_state.files, err))
    end)
  end)
  if not ok then
    set_validation(bufnr, view_state, {
      status = "blocked",
      message = "blocked - " .. tostring(validation_err),
    })
  end
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
  validate_async(bufnr, view_state)
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

function M.submit(bufnr)
  local attachment = state.get_buffer(bufnr)
  if not attachment or attachment.kind ~= "commit" then
    return nil, errors.new("commit_buffer_missing", "could not locate the CVS commit buffer state")
  end

  local view_state = attachment.view_state
  if view_state.phase == "queued" or view_state.phase == "running" then
    return nil, errors.new("commit_in_progress", "a CVS commit is already in progress for this buffer")
  end

  local validation = view_state.validation or {}
  if validation.status ~= "ready" then
    local message = "CVS state validation is still running"
    if validation.status == "blocked" then
      message = validation.message
    end
    local err = errors.new("commit_validation_" .. (validation.status or "pending"), message)
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
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
      local function complete(status_snapshot, status_err)
        local ok, callback_err = pcall(function()
          local messages = vim.deepcopy(result.stdout)
          vim.list_extend(messages, result.stderr)
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
        complete(nil, refresh_err)
      end
    end)
  end, function(queue_err)
    util.notify(("CVS commit queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return command
end

M._build_view_state = build_view_state
M._validate_snapshot = validate_snapshot

return M
