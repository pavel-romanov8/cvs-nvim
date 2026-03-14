local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local parse = require("cvs.features.update.parse")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")
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

local function build_state(phase, workspace, command, opts)
  return {
    phase = phase,
    workspace = workspace,
    command = command,
    scope_label = scope_label(workspace, opts),
    started_at = os.date("%Y-%m-%d %H:%M:%S"),
    messages = {},
  }
end

local function refresh_status(opts)
  local ok, result = pcall(require("cvs.features.status.service").collect, opts)
  if ok then
    return result
  end

  return nil
end

local function complete_state(base, result, parsed)
  return vim.tbl_extend("force", base, {
    phase = "done",
    result = result,
    parsed = parsed,
    messages = vim.deepcopy(parsed.messages or {}),
    completed_at = os.date("%Y-%m-%d %H:%M:%S"),
  })
end

function M.run(opts)
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

  local command = cmd.update(opts)
  local phase = queue.is_busy(workspace.root_dir) and "queued" or "running"
  local view_state = build_state(phase, workspace, command, opts)
  local bufnr = require("cvs.features.update.buffer").open(view_state, opts)

  queue.enqueue(workspace.root_dir, function(done)
    require("cvs.features.update.buffer").update(bufnr, vim.tbl_extend("force", view_state, {
      phase = "running",
    }))

    runner.run(command, {
      cwd = workspace.root_dir,
    }, function(result)
      local ok, callback_err = pcall(function()
        local combined = vim.deepcopy(result.stdout)
        vim.list_extend(combined, result.stderr)

        local parsed = parse.parse(combined)
        local final_state = complete_state(view_state, result, parsed)
        final_state.status_snapshot = refresh_status(opts)

        require("cvs.features.update.buffer").update(bufnr, final_state)

        if #parsed.items > 0 or parsed.has_conflicts then
          events.emit("CvsChanged", {
            root_dir = workspace.root_dir,
            result = result,
            parsed = parsed,
          })
        end

        if parsed.has_conflicts then
          util.notify("CVS update completed with conflicts.", vim.log.levels.WARN)
        elseif result.code ~= 0 then
          util.notify(("CVS update exited with code %d."):format(result.code), vim.log.levels.WARN)
        else
          util.notify("CVS update completed.")
        end
      end)

      if not ok then
        require("cvs.features.update.buffer").update(bufnr, vim.tbl_extend("force", view_state, {
          phase = "done",
          completed_at = os.date("%Y-%m-%d %H:%M:%S"),
          messages = { ("Internal error: %s"):format(callback_err) },
        }))
        util.notify(("CVS update failed internally: %s"):format(callback_err), vim.log.levels.ERROR)
      end

      done()
    end)
  end, function(queue_err)
    util.notify(("CVS update queue error: %s"):format(queue_err), vim.log.levels.ERROR)
  end)

  return bufnr
end

return M
