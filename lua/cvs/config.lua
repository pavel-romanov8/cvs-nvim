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
  status = {
    cache = {
      enabled = true,
      ttl_ms = 300000,
    },
  },
  ui = {
    default_kind = "tab",
    floating = {
      border = "rounded",
      width = 0.8,
      height = 0.8,
    },
    status = {
      kind = "split",
      height = 0.5,
    },
    session = {
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
      kind = "left_vsplit",
      width = 28,
      author_width = 12,
      auto_refresh_on_save = true,
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
