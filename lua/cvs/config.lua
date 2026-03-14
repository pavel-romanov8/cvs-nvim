local M = {}

local defaults = {
  cvs = {
    bin = "cvs",
    global_args = {},
    timeout_ms = 10000,
  },
  notifications = {
    enabled = true,
  },
  ui = {
    default_kind = "tab",
    floating = {
      border = "rounded",
      width = 0.8,
      height = 0.8,
    },
    status = {
      kind = "tab",
    },
    update = {
      kind = "tab",
    },
    commit = {
      kind = "tab",
    },
    diff = {
      kind = "tab",
    },
    log = {
      kind = "tab",
    },
    annotate = {
      kind = "tab",
    },
    conflicts = {
      kind = "tab",
    },
  },
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.values
end

function M.get()
  return M.values
end

return M
