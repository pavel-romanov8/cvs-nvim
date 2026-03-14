local capabilities = require("cvs.cvs.capabilities")
local cmd = require("cvs.cvs.cmd")
local context = require("cvs.cvs.context")
local errors = require("cvs.core.errors")
local events = require("cvs.core.events")
local parse = require("cvs.features.status.parse")
local runner = require("cvs.cvs.runner")
local state = require("cvs.core.state")
local util = require("cvs.core.util")

local M = {}

function M.collect(opts)
  opts = opts or {}

  local workspace, err = context.detect(opts.path)
  if not workspace then
    return nil, err
  end

  local snapshot = {
    workspace = workspace,
    files = {},
    messages = {},
    generated_at = os.date("%Y-%m-%d %H:%M:%S"),
  }

  local caps = capabilities.detect()
  if not caps.executable then
    snapshot.messages[#snapshot.messages + 1] = ("CVS executable is not available: %s"):format(caps.bin)
  else
    snapshot.result = runner.run(cmd.status(opts), {
      cwd = workspace.root_dir,
    })

    local parsed = parse.parse(snapshot.result.stdout)
    snapshot.files = parsed.files
    snapshot.messages = vim.list_extend(parsed.messages, snapshot.result.stderr)
  end

  state.set_snapshot(workspace.root_dir, snapshot)
  events.emit("CvsStatusRefreshed", { root_dir = workspace.root_dir })

  return snapshot
end

function M.open(opts)
  local snapshot, err = M.collect(opts)
  if not snapshot then
    util.notify(errors.to_string(err), vim.log.levels.ERROR)
    return nil, err
  end

  return require("cvs.features.status.buffer").open(snapshot, opts)
end

return M
