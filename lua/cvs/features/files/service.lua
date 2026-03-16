local cmd = require("cvs.cvs.cmd")
local capabilities = require("cvs.cvs.capabilities")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local util = require("cvs.core.util")

local M = {}

local function scope_label(workspace, path)
  if not path or path == "" then
    return "current buffer"
  end

  local prefix = workspace.root_dir .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end

  return path
end

local function resolve_target_path(opts, action_name)
  if opts.path and opts.path ~= "" then
    return util.resolve_path(opts.path)
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" then
    return util.resolve_path(current)
  end

  return nil, errors.new("path_missing", ("%s requires a file or directory path"):format(action_name or "CvsAdd"))
end

local function refresh_status(opts)
  local ok, result = pcall(require("cvs.features.status.service").collect, opts)
  if ok then
    return result
  end

  return nil
end

local function run_mutation(action)
  local opts = action.opts or {}
  local target_path, path_err = resolve_target_path(opts, action.command_name)
  if not target_path then
    util.notify(errors.to_string(path_err), vim.log.levels.ERROR)
    return nil, path_err
  end

  opts = vim.tbl_extend("force", {}, opts, { path = target_path })

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

  local command = action.build_command(opts)
  local label = scope_label(workspace, target_path)
  if queue.is_busy(workspace.root_dir) then
    util.notify(("Queued CVS %s for %s."):format(action.operation, label))
  end

  queue.enqueue(workspace.root_dir, function(done)
    runner.run(command, {
      cwd = workspace.root_dir,
    }, function(result)
      local ok, callback_err = pcall(function()
        refresh_status(opts)

        if result.code == 0 then
          events.emit("CvsChanged", {
            root_dir = workspace.root_dir,
            result = result,
            operation = action.operation,
            path = target_path,
          })
          util.notify((action.success_message):format(label))
        else
          local message = result.stderr[1]
            or result.stdout[1]
            or ("CVS %s exited with code %d."):format(action.operation, result.code)
          util.notify(message, vim.log.levels.WARN)
        end

        if opts.on_complete then
          opts.on_complete(result, {
            workspace = workspace,
            label = label,
            path = target_path,
            command = command,
            operation = action.operation,
          })
        end
      end)

      if not ok then
        util.notify(("CVS %s failed internally: %s"):format(action.operation, callback_err), vim.log.levels.ERROR)
      end

      done()
    end)
  end, function(queue_err)
    util.notify(("CVS %s queue error: %s"):format(action.operation, queue_err), vim.log.levels.ERROR)
  end)

  return command
end

function M.add(opts)
  return run_mutation({
    opts = opts,
    command_name = "CvsAdd",
    operation = "add",
    success_message = "Added %s to CVS.",
    build_command = cmd.add,
  })
end

function M.remove(opts)
  return run_mutation({
    opts = opts,
    command_name = "CvsRemove",
    operation = "remove",
    success_message = "Scheduled %s for removal.",
    build_command = cmd.remove,
  })
end

M._resolve_target_path = resolve_target_path
M._scope_label = scope_label

return M
