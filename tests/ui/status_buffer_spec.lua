local config = require("cvs.config")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")
local status_buffer = require("cvs.features.status.buffer")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  state.buffers = {}
  state.workspaces = {}
  config.setup()
  require("cvs.ui.highlights").setup()

  local source_bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, source_bufnr)
  local source_win = vim.api.nvim_get_current_win()
  local source_height = vim.api.nvim_win_get_height(source_win)

  local view_state = {
    opts = {},
    workspace = {
      root_dir = "/tmp/example",
    },
    scope_label = "workspace",
    generated_at = "2026-07-31 12:00:00",
    total_count = 2,
    counts = {
      modified = 1,
      added = 1,
    },
    sections = {
      {
        kind = "modified",
        title = "Modified",
        items = {
          { code = "M", path = "changed.lua", status = "modified" },
        },
      },
      {
        kind = "added",
        title = "Added",
        items = {
          { code = "A", path = "new.lua", status = "added" },
        },
      },
    },
    messages = {},
  }
  local bufnr, winid = status_buffer.open(view_state, {})

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "status opens in a split")
  assert_eq(vim.api.nvim_win_get_height(winid), math.floor(source_height / 2), "status split uses half the source height")
  assert_eq(vim.bo[bufnr].filetype, "cvs-status", "status buffer has its filetype")

  local existing_bufnr, existing_win = service.open({})
  assert_eq(existing_bufnr, bufnr, ":Cvs reuses the current status buffer")
  assert_eq(existing_win, winid, ":Cvs does not create another status split")

  local original_collect = service.collect
  local forced
  service.collect = function(opts)
    forced = opts.force
    return {
      workspace = view_state.workspace,
      generated_at = view_state.generated_at,
      files = {
        { code = "M", path = "changed.lua", status = "modified" },
        { code = "A", path = "new.lua", status = "added" },
      },
      messages = {},
    }
  end
  service.open({ force = true })
  service.collect = original_collect
  assert_eq(forced, true, ":Cvs! refreshes the current status buffer")

  local namespace = vim.api.nvim_get_namespaces()["cvs-status"]
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
  local groups = {}
  for _, extmark in ipairs(extmarks) do
    groups[extmark[4].hl_group] = true
  end

  assert_true(groups.CvsHeader, "status header is highlighted")
  assert_true(groups.CvsSection, "status sections are highlighted")
  assert_true(groups.CvsStatusModified, "modified files are highlighted")
  assert_true(groups.CvsStatusAdded, "added files are highlighted")

  local added = vim.api.nvim_get_hl(0, { name = "CvsStatusAdded", link = true })
  assert_eq(added.link, "Added", "added files inherit the active theme")
  local added_style = vim.api.nvim_get_hl(0, { name = "CvsStatusAdded", link = false })
  assert_true(next(added_style) ~= nil, "added file highlighting resolves to a visible style")

  local refreshed = vim.deepcopy(view_state)
  refreshed.counts = { removed = 1 }
  refreshed.total_count = 1
  refreshed.sections = {
    {
      kind = "removed",
      title = "Removed",
      items = {
        { code = "R", path = "old.lua", status = "removed" },
      },
    },
  }
  status_buffer.update(bufnr, refreshed)

  extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
  groups = {}
  for _, extmark in ipairs(extmarks) do
    groups[extmark[4].hl_group] = true
  end
  assert_true(groups.CvsStatusRemoved, "refresh reapplies status highlights")

  vim.api.nvim_set_hl(0, "CvsStatusAdded", {})
  vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
  added = vim.api.nvim_get_hl(0, { name = "CvsStatusAdded", link = true })
  assert_eq(added.link, "Added", "colorscheme changes restore status links")

  vim.api.nvim_win_close(winid, true)
end
