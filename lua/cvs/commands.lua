local M = {}

local initialized = false

local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
end

local function command_opts(args)
  local opts = {
    path = args.args ~= "" and args.args or nil,
  }

  if args.bang then
    opts.force = true
  end

  local modifiers = args.smods or {}
  if modifiers.tab and modifiers.tab >= 0 then
    opts.kind = "tab"
  elseif modifiers.vertical then
    opts.kind = "vsplit"
  elseif modifiers.horizontal then
    opts.kind = "split"
  end

  if modifiers.split and modifiers.split ~= "" then
    opts.position = modifiers.split
  end

  return opts
end

local function log_command_opts(args)
  local opts = command_opts({ args = "", bang = args.bang, smods = args.smods })
  local tokens = args.fargs or {}
  local index = 1
  local positional = false
  while index <= #tokens do
    local token = tokens[index]
    if not positional and token == "--" then
      positional = true
    elseif not positional and (token == "-d" or token == "--days") then
      index = index + 1
      local days = tonumber(tokens[index])
      if not days or days < 0 or days ~= math.floor(days) then
        return nil, token .. " requires a non-negative whole number"
      end
      opts.repository_days = days
    elseif not positional and (token == "-c" or token == "--commits") then
      index = index + 1
      local value = tokens[index] or ""
      local first, last = value:match("^(%d+)%-(%d+)$")
      if first then
        first, last = tonumber(first), tonumber(last)
        if first < 1 or last < first then
          return nil, token .. " requires N or an ascending START-END range"
        end
        opts.repository_commit_from = first
        opts.repository_max_commits = last
      else
        local count = tonumber(value)
        if not count or count < 0 or count ~= math.floor(count) then
          return nil, token .. " requires N or an ascending START-END range"
        end
        opts.repository_commit_from = 1
        opts.repository_max_commits = count
      end
    elseif not positional and token:sub(1, 1) == "-" then
      return nil, "unknown option: " .. token
    elseif opts.path then
      return nil, "only one path may be provided"
    else
      opts.path = token
    end
    index = index + 1
  end
  return opts
end

function M.setup()
  if initialized then
    return
  end

  create("Cvs", function(args)
    require("cvs").status(command_opts(args))
  end, {
    bang = true,
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsStatus", function(args)
    require("cvs").status(command_opts(args))
  end, {
    bang = true,
    nargs = "?",
    complete = "file",
    desc = "Open the CVS status view",
  })

  create("CvsUpdate", function(args)
    require("cvs").update(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Run or preview a CVS update workflow",
  })

  create("CvsAdd", function(args)
    require("cvs").add(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Add a file or directory to CVS",
  })

  create("CvsRemove", function(args)
    require("cvs").remove(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Remove a file or directory from CVS",
  })

  create("CvsCommit", function(args)
    require("cvs").commit(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS commit workflow",
  })

  create("CvsDiff", function(args)
    local opts = command_opts(args)
    opts.stream = args.bang or nil
    opts.force = nil
    require("cvs").diff(opts)
  end, {
    bang = true,
    nargs = "?",
    complete = "file",
    desc = "Diff a working file against its CVS base revision",
  })

  create("Cdiffsplit", function(args)
    require("cvs").diff({
      source_bufnr = vim.api.nvim_get_current_buf(),
      source_win = vim.api.nvim_get_current_win(),
      stream = args.bang or nil,
      kind = args.bang and "vsplit" or nil,
    })
  end, {
    bang = true,
    desc = "Diff the current file against its CVS base revision",
  })

  create("CvsLog", function(args)
    local opts, err = log_command_opts(args)
    if not opts then
      require("cvs.core.util").notify("CvsLog: " .. err, vim.log.levels.ERROR)
      return
    end
    require("cvs").log(opts)
  end, {
    bang = true,
    nargs = "*",
    complete = "file",
    desc = "Open the CVS log workflow",
  })

  create("CvsRevert", function(args)
    local opts = command_opts(args)
    opts.commit_id = args.args
    opts.path = nil
    require("cvs").revert(opts)
  end, {
    nargs = 1,
    desc = "Prepare a revert for a complete CVS commit ID",
  })

  create("CvsAnnotate", function(args)
    require("cvs").annotate(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS annotate workflow",
  })

  create("CvsConflicts", function(args)
    require("cvs").conflicts(command_opts(args))
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open the CVS conflict workflow",
  })

  initialized = true
end

return M
