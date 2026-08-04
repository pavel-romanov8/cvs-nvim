local cmd = require("cvs.cvs.cmd")
local capabilities = require("cvs.cvs.capabilities")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
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

local function normalize_workspace_files(workspace, files)
  if not workspace or not workspace.root_dir then
    return nil, nil, errors.new("workspace_missing", "bulk CVS file operations require an explicit workspace")
  end

  local root_dir = util.normalize(workspace.root_dir)
  local command_files = {}
  local target_paths = {}
  local seen = {}

  for _, file in ipairs(files or {}) do
    local normalized = util.normalize(file)
    if normalized then
      local target = vim.startswith(normalized, "/") and normalized or util.normalize(util.path_join(root_dir, normalized))
      local inside_workspace = target == root_dir
        or root_dir == "/"
        or vim.startswith(target, root_dir .. "/")
      if not inside_workspace or target == root_dir then
        return nil, nil, errors.new(
          "path_outside_workspace",
          ("CVS target is outside the workspace: %s"):format(file)
        )
      end

      local relative = root_dir == "/" and target:sub(2) or target:sub(#root_dir + 2)
      if not seen[relative] then
        seen[relative] = true
        command_files[#command_files + 1] = relative
        target_paths[#target_paths + 1] = target
      end
    end
  end

  if #command_files == 0 then
    return nil, nil, errors.new("files_missing", "select at least one file for the CVS operation")
  end

  return command_files, target_paths
end

local function run_mutation(action)
  local opts = action.opts or {}
  local workspace = opts.workspace
  local command_files
  local target_paths
  local err

  if opts.files and #opts.files > 0 then
    command_files, target_paths, err = normalize_workspace_files(workspace, opts.files)
    if not command_files then
      util.notify(errors.to_string(err), vim.log.levels.ERROR)
      return nil, err
    end
  else
    local target_path
    target_path, err = resolve_target_path(opts, action.command_name)
    if not target_path then
      util.notify(errors.to_string(err), vim.log.levels.ERROR)
      return nil, err
    end

    workspace, err = context.detect(target_path)
    if not workspace then
      util.notify(errors.to_string(err), vim.log.levels.ERROR)
      return nil, err
    end

    command_files = { target_path }
    target_paths = { target_path }
  end

  local caps = capabilities.detect()
  if not caps.executable then
    err = errors.new("cvs_missing", ("CVS executable is not available: %s"):format(caps.bin))
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  local command_opts = vim.tbl_extend("force", {}, opts)
  command_opts.path = nil
  command_opts.files = command_files
  command_opts.workspace = nil
  local command = action.build_command(command_opts)
  local label = #target_paths == 1 and scope_label(workspace, target_paths[1]) or ("%d files"):format(#target_paths)
  if queue.is_busy(workspace.root_dir) then
    util.notify(("Queued CVS %s for %s."):format(action.operation, label))
  end

  queue.enqueue(workspace.root_dir, function(done)
    runner.run(command, {
      cwd = workspace.root_dir,
    }, function(result)
      local ok, callback_err = pcall(function()
        state.invalidate_status_cache(workspace.root_dir)

        if result.code == 0 then
          events.emit("CvsChanged", {
            root_dir = workspace.root_dir,
            result = result,
            operation = action.operation,
            path = #target_paths == 1 and target_paths[1] or nil,
            files = command_files,
            binary = opts.binary == true,
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
            path = #target_paths == 1 and target_paths[1] or nil,
            files = command_files,
            paths = target_paths,
            command = command,
            operation = action.operation,
            binary = opts.binary == true,
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
M._normalize_workspace_files = normalize_workspace_files

return M
