local config = require("cvs.config")
local commit_service = require("cvs.features.commit.service")
local diff_service = require("cvs.features.diff.service")
local files_service = require("cvs.features.files.service")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")
local status_buffer = require("cvs.features.status.buffer")

local function find_line(bufnr, text)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find(text, 1, true) then return row end
  end
end

local function text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  state.buffers = {}
  state.workspaces = {}
  config.setup({ notifications = { enabled = false } })

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir .. "/CVS", "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, temp_dir .. "/CVS/Root")
  vim.fn.writefile({ "module" }, temp_dir .. "/CVS/Repository")
  vim.fn.writefile({ "source" }, temp_dir .. "/source.lua")
  vim.fn.writefile({ "changed" }, temp_dir .. "/changed.lua")
  vim.fn.writefile({ "new" }, temp_dir .. "/new.lua")

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_name(source_bufnr, temp_dir .. "/source.lua")
  vim.api.nvim_win_set_buf(0, source_bufnr)

  local view_state = service._build_view_state({
    workspace = { root_dir = temp_dir },
    generated_at = "2026-07-31 12:00:00",
    files = {
      { code = "M", path = "changed.lua", status = "modified" },
      { code = "A", path = "new.lua", status = "added" },
      { code = "?", path = "unknown.lua", status = "unknown" },
    },
    messages = {},
  }, {}, {})

  local original_collect = diff_service.collect
  local original_diff_open = diff_service.open
  local original_commit_open = commit_service.open
  local original_discard = files_service.discard
  local bufnr

  local ok, err = pcall(function()
    local winid
    bufnr, winid = status_buffer.open(view_state, {})
    assert(vim.bo[bufnr].filetype == "cvs-status", "status opens its dedicated buffer")
    assert(text(bufnr):find("M  changed.lua", 1, true), "status renders changed files")

    local requested_diff
    diff_service.collect = function(opts, callback)
      requested_diff = opts.path
      callback({ parsed = { lines = { "@@ -1 +1 @@", "-old", "+new" } } })
      return { mocked = true }
    end
    vim.api.nvim_win_set_cursor(winid, { find_line(bufnr, "M  changed.lua"), 0 })
    service.toggle_inline_diff(bufnr)
    assert(requested_diff == temp_dir .. "/changed.lua", "inline diff targets the selected file")
    assert(text(bufnr):find("   +new", 1, true), "inline diff is rendered in place")

    service.toggle_selection(bufnr, find_line(bufnr, "M  changed.lua"))
    service.toggle_selection(bufnr, find_line(bufnr, "A  new.lua"))
    local selected = state.get_buffer(bufnr).view_state
    assert(selected.selected_count == 2, "file rows build a commit selection")
    assert(find_line(bufnr, "Selected (2)"), "selected files move into one section")

    local commit_opts
    commit_service.open = function(opts)
      commit_opts = opts
      return 901, 902
    end
    vim.api.nvim_win_set_cursor(winid, { find_line(bufnr, "Selected (2)"), 0 })
    service.commit_selected(bufnr)
    assert(#commit_opts.files == 2 and commit_opts.source_bufnr == bufnr,
      "commit action forwards only the status selection and source buffer")

    local discard_opts
    files_service.discard = function(opts)
      discard_opts = opts
      return true
    end
    service._confirm_discard = function() return true end
    service.toggle_selection(bufnr, find_line(bufnr, "Selected (2)"))
    vim.api.nvim_win_set_cursor(winid, { find_line(bufnr, "M  changed.lua"), 0 })
    service.discard_current(bufnr)
    assert(discard_opts.items[1].path == "changed.lua", "discard delegates the selected status item")

    local diff_opts
    diff_service.open = function(opts)
      diff_opts = opts
      return { mocked = true }
    end
    service.diff_current(bufnr)
    assert(diff_opts.path == temp_dir .. "/changed.lua", "full diff resolves the selected working file")

    service.toggle_selection(bufnr, find_line(bufnr, "M  changed.lua"))
    status_buffer.close(bufnr)
    assert(vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0,
      "closing hides rather than destroys status state")
    local reopened_bufnr, reopened_win = service.open({})
    assert(reopened_bufnr == bufnr and vim.api.nvim_win_is_valid(reopened_win),
      "opening status reuses the hidden workspace buffer")
    assert(state.get_buffer(bufnr).view_state.selected["changed.lua"],
      "hidden status retains its commit selection")

    vim.api.nvim_win_set_cursor(reopened_win, { find_line(bufnr, "M  changed.lua"), 0 })
    if state.get_buffer(bufnr).view_state.inline_diff then
      service.toggle_inline_diff(bufnr)
    end
    local pending
    local killed = false
    diff_service.collect = function(_, callback)
      pending = callback
      return { kill = function() killed = true end }
    end
    service.toggle_inline_diff(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert(killed, "wiping status cancels an in-flight inline diff")
    assert(pcall(pending, nil, { kind = "cancelled", message = "cancelled" }),
      "late inline-diff completion is ignored")
  end)

  diff_service.collect = original_collect
  diff_service.open = original_diff_open
  commit_service.open = original_commit_open
  files_service.discard = original_discard
  service._confirm_discard = nil
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.fn.delete(temp_dir, "rf")
  if not ok then error(err) end
end
