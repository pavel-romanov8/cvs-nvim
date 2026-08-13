local config = require("cvs.config")
local commit_service = require("cvs.features.commit.service")
local diff_service = require("cvs.features.diff.service")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")
local status_buffer = require("cvs.features.status.buffer")
local files_service = require("cvs.features.files.service")
local runner = require("cvs.cvs.runner")

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

local function find_line(bufnr, text)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find(text, 1, true) then
      return row
    end
  end

  return nil
end

return function()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  state.buffers = {}
  state.workspaces = {}
  config.setup()
  require("cvs.ui.highlights").setup()

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")
  vim.fn.mkdir(temp_dir .. "/CVS", "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, temp_dir .. "/CVS/Root")
  vim.fn.writefile({ "module" }, temp_dir .. "/CVS/Repository")
  vim.fn.writefile({ "source" }, temp_dir .. "/source.lua")
  vim.fn.writefile({ "changed" }, temp_dir .. "/changed.lua")
  vim.fn.writefile({ "new" }, temp_dir .. "/new.lua")
  vim.fn.writefile({ "unknown one" }, temp_dir .. "/unknown-one.lua")
  vim.fn.writefile({ "unknown two" }, temp_dir .. "/unknown-two.lua")
  vim.fn.writefile({ "unknown three" }, temp_dir .. "/unknown-three.lua")

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_name(source_bufnr, temp_dir .. "/source.lua")
  vim.api.nvim_win_set_buf(0, source_bufnr)
  local source_win = vim.api.nvim_get_current_win()
  local source_height = vim.api.nvim_win_get_height(source_win)

  local view_state = service._build_view_state({
    workspace = {
      root_dir = temp_dir,
    },
    generated_at = "2026-07-31 12:00:00",
    files = {
      { code = "M", path = "changed.lua", status = "modified" },
      { code = "A", path = "new.lua", status = "added" },
      { code = "?", path = "unknown-one.lua", status = "unknown" },
      { code = "?", path = "unknown-two.lua", status = "unknown" },
      { code = "?", path = "unknown-three.lua", status = "unknown" },
    },
    messages = {},
  }, {}, {})
  local bufnr, winid = status_buffer.open(view_state, {})

  assert_eq(#vim.api.nvim_tabpage_list_wins(0), 2, "status opens in a split")
  assert_eq(vim.api.nvim_win_get_height(winid), math.floor(source_height / 2), "status split uses half the source height")
  assert_eq(vim.bo[bufnr].filetype, "cvs-status", "status buffer has its filetype")
  vim.api.nvim_set_current_win(winid)
  assert_eq(vim.fn.maparg("-", "n", false, true).desc, "Toggle CVS commit selection", "normal selection mapping")
  assert_eq(vim.fn.maparg("-", "x", false, true).desc, "Toggle CVS commit selection", "visual selection mapping")
  assert_eq(vim.fn.maparg("a", "x", false, true).desc, "Add selected files to CVS", "visual add mapping")
  assert_eq(vim.fn.maparg("A", "n", false, true).desc, "Add current file to CVS as binary", "binary add mapping")
  assert_eq(vim.fn.maparg("A", "x", false, true).desc, "Add selected files to CVS as binary", "visual binary add mapping")
  assert_eq(vim.fn.maparg("cc", "n", false, true).desc, "Commit selected CVS files", "commit selection mapping")
  assert_eq(vim.fn.maparg("dd", "n", false, true).desc, "Diff current file against its CVS base", "full diff mapping")
  assert_eq(vim.fn.maparg("o", "n", false, true).desc, "Open current file in a split", "split mapping")
  assert_eq(vim.fn.maparg("gO", "n", false, true).desc, "Open current file in a vertical split", "vertical split mapping")
  assert_eq(vim.fn.maparg("O", "n", false, true).desc, "Open current file in a tab", "tab mapping")
  assert_eq(vim.fn.maparg("p", "n", false, true).desc, "Open current file in preview", "preview mapping")
  assert_eq(state.get_buffer(bufnr).view_state.selected_count, 0, "selection starts empty")

  local original_collect = diff_service.collect
  local diff_path
  diff_service.collect = function(opts, callback)
    diff_path = opts.path
    callback({
      parsed = {
        lines = {
          "@@ -1 +1 @@",
          "-old",
          "+changed",
        },
      },
    }, nil)
    return { mocked = true }
  end

  service.toggle_inline_diff(bufnr)
  diff_service.collect = original_collect

  assert_eq(diff_path, temp_dir .. "/changed.lua", "inline diff requests the selected file")
  local status_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  assert_true(status_text:find("   @@ -1 +1 @@", 1, true) ~= nil, "inline diff renders its hunk")
  assert_true(status_text:find("   +changed", 1, true) ~= nil, "inline diff renders added lines")

  local modified_row = find_line(bufnr, "M  changed.lua")
  local diff_row = find_line(bufnr, "@@ -1 +1 @@")
  local added_row = find_line(bufnr, "A  new.lua")
  vim.api.nvim_win_set_cursor(winid, { diff_row, 0 })
  status_buffer.update(bufnr, vim.deepcopy(state.get_buffer(bufnr).view_state))
  assert_true(
    vim.api.nvim_get_current_line():find("@@ -1 +1 @@", 1, true) ~= nil,
    "rerender preserves the cursor's inline-diff offset"
  )
  assert_eq(service.toggle_selection(bufnr, modified_row), true, "file row selects its file")
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], true, "modified file is selected")
  assert_eq(service.toggle_selection(bufnr, diff_row), false, "inline diff row toggles its parent file")
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], nil, "inline diff row clears its parent")

  modified_row = find_line(bufnr, "M  changed.lua")
  added_row = find_line(bufnr, "A  new.lua")
  local added_heading = find_line(bufnr, "Added (1)")
  local heading_range = status_buffer.get_targets(bufnr, modified_row, added_heading)
  assert_eq(#heading_range, 1, "range does not expand a crossed section heading")
  assert_eq(heading_range[1].path, "changed.lua", "range includes only covered file rows")
  assert_eq(service.toggle_selection(bufnr, modified_row, added_row), true, "range selects all unique files")
  assert_eq(state.get_buffer(bufnr).view_state.selected_count, 2, "range deduplicates inline diff rows")
  local selected_heading = find_line(bufnr, "Selected (2)")
  assert_true(selected_heading ~= nil, "selected files render in a dedicated section")
  assert_true(find_line(bufnr, "[x]") == nil, "selected files do not render checkboxes")
  assert_eq(service.toggle_selection(bufnr, selected_heading), false, "selected heading clears all selected files")
  assert_eq(state.get_buffer(bufnr).view_state.selected_count, 0, "selected section is cleared")

  local modified_heading = find_line(bufnr, "Modified (1)")
  assert_eq(service.toggle_selection(bufnr, modified_heading), true, "section heading selects its files")
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], true, "heading selects modified file")

  service.toggle_inline_diff(bufnr)
  status_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  assert_true(status_text:find("   @@ -1 +1 @@", 1, true) == nil, "inline diff collapses on the second toggle")

  local missing_state = service._build_view_state({
    workspace = view_state.workspace,
    generated_at = view_state.generated_at,
    files = {
      { code = "M", path = "changed.lua", status = "modified" },
      { code = "A", path = "new.lua", status = "added" },
      { code = "R", path = "missing-one.lua", status = "missing" },
      { code = "R", path = "missing-two.lua", status = "missing" },
      { code = "?", path = "unknown-one.lua", status = "unknown" },
      { code = "?", path = "unknown-two.lua", status = "unknown" },
      { code = "?", path = "unknown-three.lua", status = "unknown" },
    },
    messages = {},
  }, {}, state.get_buffer(bufnr).view_state)
  status_buffer.update(bufnr, missing_state)
  local missing_heading = find_line(bufnr, "Missing (2)")
  local missing_targets = status_buffer.get_remove_targets(bufnr, missing_heading)
  assert_eq(#missing_targets, 2, "remove resolves every missing file from its heading")

  local original_remove = files_service.remove
  local original_remove_collect = service.collect_async
  local remove_opts
  files_service.remove = function(opts)
    remove_opts = opts
    opts.on_complete({ code = 0, stdout = {}, stderr = {} })
    return { "cvs", "remove" }
  end
  service.collect_async = function(_, callback)
    callback({
      workspace = view_state.workspace,
      generated_at = view_state.generated_at,
      files = {
        { code = "M", path = "changed.lua", status = "modified" },
        { code = "A", path = "new.lua", status = "added" },
        { code = "R", path = "missing-one.lua", status = "removed" },
        { code = "R", path = "missing-two.lua", status = "removed" },
        { code = "?", path = "unknown-one.lua", status = "unknown" },
        { code = "?", path = "unknown-two.lua", status = "unknown" },
        { code = "?", path = "unknown-three.lua", status = "unknown" },
      },
      messages = {},
    })
  end
  vim.api.nvim_win_set_cursor(winid, { missing_heading, 0 })
  service.remove_current(bufnr)
  assert_eq(remove_opts.workspace.root_dir, temp_dir, "heading remove uses status workspace")
  assert_eq(#remove_opts.files, 2, "heading remove passes every missing file")
  assert_eq(remove_opts.files[1], "missing-one.lua", "heading remove includes first missing file")
  assert_eq(remove_opts.files[2], "missing-two.lua", "heading remove includes second missing file")
  assert_true(find_line(bufnr, "Removed (2)") ~= nil, "successful heading remove refreshes files as removed")
  files_service.remove = original_remove
  service.collect_async = original_remove_collect
  status_buffer.update(bufnr, service._build_view_state({
    workspace = view_state.workspace,
    generated_at = view_state.generated_at,
    files = {
      { code = "M", path = "changed.lua", status = "modified" },
      { code = "A", path = "new.lua", status = "added" },
      { code = "?", path = "unknown-one.lua", status = "unknown" },
      { code = "?", path = "unknown-two.lua", status = "unknown" },
      { code = "?", path = "unknown-three.lua", status = "unknown" },
    },
    messages = {},
  }, {}, state.get_buffer(bufnr).view_state))

  local original_add = files_service.add
  local original_add_collect = service.collect_async
  local add_result = { code = 1, stdout = {}, stderr = { "add failed" } }
  local add_opts
  local added_paths = {}
  files_service.add = function(opts)
    add_opts = opts
    if add_result.code == 0 then
      for _, path in ipairs(opts.files) do
        added_paths[path] = true
      end
    end
    opts.on_complete(add_result)
    return { "cvs", "add" }
  end
  service.collect_async = function(_, callback)
    local function file(path)
      local added = added_paths[path] == true
      return {
        code = added and "A" or "?",
        path = path,
        status = added and "added" or "unknown",
      }
    end

    callback({
      workspace = view_state.workspace,
      generated_at = view_state.generated_at,
      files = {
        { code = "M", path = "changed.lua", status = "modified" },
        { code = "A", path = "new.lua", status = "added" },
        file("unknown-one.lua"),
        file("unknown-two.lua"),
        file("unknown-three.lua"),
      },
      messages = {},
    })
  end

  local unknown_one_row = find_line(bufnr, "?  unknown-one.lua")
  service.add_current(bufnr, unknown_one_row)
  assert_eq(#add_opts.files, 1, "current-row add passes one file")
  assert_eq(add_opts.files[1], "unknown-one.lua", "current-row add passes the target path")
  assert_eq(state.get_buffer(bufnr).view_state.selected["unknown-one.lua"], nil, "failed unknown add is not selected")

  local unknown_heading = find_line(bufnr, "Unknown (3)")
  local unknown_two_row = find_line(bufnr, "?  unknown-two.lua")
  local visual_add_targets = status_buffer.get_add_targets(bufnr, unknown_one_row, unknown_two_row)
  assert_eq(#visual_add_targets, 3, "visual add range resolves every covered unknown file")
  local mixed_add_targets, skipped_add_targets = status_buffer.get_add_targets(bufnr, modified_row, unknown_one_row)
  assert_eq(#mixed_add_targets, 1, "mixed add range retains its eligible file")
  assert_eq(skipped_add_targets, 2, "mixed add range counts ineligible files once")

  add_result = { code = 0, stdout = {}, stderr = {} }
  service.add_binary(bufnr, unknown_one_row)
  assert_eq(add_opts.binary, true, "binary add marks the file-service operation")
  assert_eq(#add_opts.files, 1, "binary current-row add passes one file")
  assert_eq(add_opts.files[1], "unknown-one.lua", "binary add passes its unknown target")
  assert_eq(state.get_buffer(bufnr).view_state.selected["unknown-one.lua"], true, "binary-added file is selected")

  unknown_heading = find_line(bufnr, "Unknown (2)")
  local binary_heading_targets = status_buffer.get_binary_add_targets(bufnr, unknown_heading)
  assert_eq(#binary_heading_targets, 2, "binary add resolves every unknown file from its heading")
  service.add_current(bufnr, unknown_heading)
  assert_eq(add_opts.workspace.root_dir, temp_dir, "heading add uses status workspace")
  assert_eq(#add_opts.files, 2, "heading add passes every unknown file")
  assert_eq(state.get_buffer(bufnr).view_state.selected["unknown-one.lua"], true, "added file is selected")
  assert_eq(state.get_buffer(bufnr).view_state.selected["unknown-two.lua"], true, "bulk-added file is selected")
  assert_eq(state.get_buffer(bufnr).view_state.selected["unknown-three.lua"], true, "second bulk-added file is selected")

  files_service.add = original_add
  service.collect_async = original_add_collect

  local existing_bufnr, existing_win = service.open({})
  assert_eq(existing_bufnr, bufnr, ":Cvs reuses the current status buffer")
  assert_eq(existing_win, winid, ":Cvs does not create another status split")

  local original_collect = service.collect_async
  local forced
  service.collect_async = function(opts, callback)
    forced = opts.force
    callback({
      workspace = view_state.workspace,
      generated_at = view_state.generated_at,
      files = {
        { code = "M", path = "changed.lua", status = "modified" },
        { code = "A", path = "new.lua", status = "added" },
      },
      messages = {},
    })
  end
  service.open({ force = true })
  service.collect_async = original_collect
  assert_eq(forced, true, ":Cvs! refreshes the current status buffer")
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], true, "refresh preserves eligible selection")
  assert_eq(state.get_buffer(bufnr).view_state.selected["new.lua"], nil, "refresh keeps unselected file clear")

  modified_row = find_line(bufnr, "M  changed.lua")
  vim.api.nvim_win_set_cursor(winid, { modified_row, 0 })
  status_buffer.close(bufnr)
  assert_true(vim.api.nvim_buf_is_valid(bufnr), "closing status retains its buffer")
  assert_eq(#vim.fn.win_findbuf(bufnr), 0, "closing status hides its buffer")
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], true, "hidden status retains selection")

  local reopened_bufnr, reopened_win = service.open({})
  assert_eq(reopened_bufnr, bufnr, ":Cvs reopens the retained status buffer")
  assert_true(vim.api.nvim_win_is_valid(reopened_win), "retained status opens in a new window")
  assert_true(
    vim.api.nvim_get_current_line():find("M  changed.lua", 1, true) ~= nil,
    "reopened status restores its cursor"
  )
  assert_eq(state.get_buffer(bufnr).view_state.selected["changed.lua"], true, "reopened status retains selection")
  winid = reopened_win

  local original_commit_open = commit_service.open
  local commit_opts
  commit_service.open = function(opts)
    commit_opts = opts
    return 999, 998
  end
  selected_heading = find_line(bufnr, "Selected (1)")
  vim.api.nvim_win_set_cursor(winid, { selected_heading, 0 })
  assert_true(vim.api.nvim_get_current_line():find("Selected (1)", 1, true) ~= nil, "commit runs from selected heading")
  local commit_bufnr, commit_win = service.commit_selected(bufnr)
  commit_service.open = original_commit_open
  assert_eq(commit_bufnr, 999, "selected commit opens its editor immediately")
  assert_eq(commit_win, 998, "selected commit returns its editor window")
  assert_eq(#commit_opts.files, 1, "selected commit passes only selected paths")
  assert_eq(commit_opts.files[1], "changed.lua", "selected commit passes selected file")
  assert_eq(commit_opts.workspace.root_dir, temp_dir, "selected commit passes explicit workspace")
  assert_eq(commit_opts.source_bufnr, bufnr, "selected commit retains source status buffer")

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
  assert_eq(added.link, "Typedef", "added files use Fugitive-style modifier highlighting")
  local added_style = vim.api.nvim_get_hl(0, { name = "CvsStatusAdded", link = false })
  assert_true(next(added_style) ~= nil, "added file highlighting resolves to a visible style")

  local modified = vim.api.nvim_get_hl(0, { name = "CvsStatusModified", link = true })
  assert_eq(modified.link, "Structure", "modified files use Fugitive-style modifier highlighting")

  for _, extmark in ipairs(extmarks) do
    local details = extmark[4]
    if details.hl_group == "CvsStatusModified" then
      assert_eq(extmark[3], 4, "modified highlighting starts at the status prefix")
      assert_eq(details.end_col, 6, "only the modified status prefix is highlighted")
    end
  end

  vim.api.nvim_set_current_win(winid)
  modified_row = find_line(bufnr, "M  changed.lua")
  vim.api.nvim_win_set_cursor(winid, { modified_row, 0 })
  service.open_current(bufnr)
  assert_eq(vim.api.nvim_get_current_win(), source_win, "Enter opens the file in the original window")
  assert_eq(
    vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)),
    vim.uv.fs_realpath(temp_dir .. "/changed.lua"),
    "Enter opens the selected file"
  )
  assert_eq(vim.api.nvim_win_get_buf(winid), bufnr, "Enter keeps the status split open")

  vim.api.nvim_set_current_win(winid)
  modified_row = find_line(bufnr, "M  changed.lua")
  vim.api.nvim_win_set_cursor(winid, { modified_row, 0 })

  local original_diff_open = diff_service.open
  local diff_opts
  diff_service.open = function(opts)
    diff_opts = opts
    return { mocked = true }
  end
  service.diff_current(bufnr)
  diff_service.open = original_diff_open
  assert_eq(
    vim.uv.fs_realpath(diff_opts.path),
    vim.uv.fs_realpath(temp_dir .. "/changed.lua"),
    "dd resolves the current working file"
  )
  assert_eq(diff_opts.stream, nil, "dd keeps the full side-by-side diff")

  local windows_before = #vim.api.nvim_tabpage_list_wins(0)
  service.open_current(bufnr, "split")
  assert_eq(#vim.api.nvim_tabpage_list_wins(0), windows_before + 1, "o opens another split")
  assert_eq(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)), vim.uv.fs_realpath(temp_dir .. "/changed.lua"), "o opens the file")
  vim.api.nvim_win_close(0, true)

  vim.api.nvim_set_current_win(winid)
  service.open_current(bufnr, "vsplit")
  assert_eq(#vim.api.nvim_tabpage_list_wins(0), windows_before + 1, "gO opens another vertical split")
  assert_eq(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)), vim.uv.fs_realpath(temp_dir .. "/changed.lua"), "gO opens the file")
  vim.api.nvim_win_close(0, true)

  vim.api.nvim_set_current_win(winid)
  local tabs_before = #vim.api.nvim_list_tabpages()
  service.open_current(bufnr, "tab")
  assert_eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "O opens another tab")
  assert_eq(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)), vim.uv.fs_realpath(temp_dir .. "/changed.lua"), "O opens the file")
  vim.cmd("tabclose!")

  vim.api.nvim_set_current_win(winid)
  service.open_current(bufnr, "preview")
  assert_eq(vim.api.nvim_get_current_win(), winid, "p keeps focus in status")
  assert_eq(#vim.api.nvim_tabpage_list_wins(0), windows_before + 1, "p opens a preview window")
  vim.cmd("pclose")

  vim.api.nvim_set_current_win(winid)
  local new_row = find_line(bufnr, "A  new.lua")
  vim.api.nvim_win_set_cursor(winid, { new_row, 0 })
  local shifted = vim.deepcopy(state.get_buffer(bufnr).view_state)
  table.insert(shifted.sections[1].items, 1, {
    code = "M",
    path = "before.lua",
    status = "modified",
    selectable = true,
    selected = false,
  })
  status_buffer.update(bufnr, shifted)
  assert_true(
    vim.api.nvim_get_current_line():find("A  new.lua", 1, true) ~= nil,
    "refresh preserves the file under the cursor"
  )

  if vim.fn.exists("+winfixbuf") == 1 then
    vim.wo[source_win].winfixbuf = true
    vim.api.nvim_set_current_win(winid)
    service.open_current(bufnr)
    local replacement_win = vim.api.nvim_get_current_win()
    assert_true(replacement_win ~= source_win, "Enter avoids a fixed-buffer origin window")
    assert_eq(vim.api.nvim_win_get_buf(winid), bufnr, "fallback keeps the status split open")
    vim.api.nvim_win_close(replacement_win, true)
    vim.wo[source_win].winfixbuf = false
  end

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
  assert_eq(added.link, "Typedef", "colorscheme changes restore status links")

  status_buffer.update(bufnr, shifted)
  vim.api.nvim_set_current_win(winid)
  modified_row = find_line(bufnr, "M  changed.lua")
  vim.api.nvim_win_set_cursor(winid, { modified_row, 0 })
  local pending_inline
  local inline_killed = false
  original_collect = diff_service.collect
  diff_service.collect = function(_, callback)
    pending_inline = callback
    return {
      kill = function()
        inline_killed = true
      end,
    }
  end
  service.toggle_inline_diff(bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  assert_true(inline_killed, "wiping status cancels its inline diff")
  assert_true(pcall(pending_inline, nil, { kind = "cancelled", message = "cancelled" }), "cancelled inline completion is ignored")
  diff_service.collect = original_collect

  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  vim.fn.delete(temp_dir, "rf")
end
