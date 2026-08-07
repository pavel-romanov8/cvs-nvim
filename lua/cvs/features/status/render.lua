local M = {}

local status_order = {
  "modified",
  "added",
  "removed",
  "unknown",
  "conflict",
  "updated",
  "patched",
}

local summary_codes = {
  modified = "M",
  added = "A",
  removed = "R",
  unknown = "?",
  conflict = "C",
  updated = "U",
  patched = "P",
}

local status_highlights = {
  modified = "CvsStatusModified",
  added = "CvsStatusAdded",
  removed = "CvsStatusRemoved",
  unknown = "CvsStatusUnknown",
  conflict = "CvsStatusConflict",
  updated = "CvsStatusUpdated",
  patched = "CvsStatusPatched",
}

local function highlight(highlights, row, group, start_col, end_col)
  highlights[#highlights + 1] = {
    row = row,
    group = group,
    start_col = start_col or 0,
    end_col = end_col or -1,
  }
end

local function highlight_label(highlights, row, line, value_group)
  local colon = line:find(":", 1, true)
  if not colon then
    return
  end

  highlight(highlights, row, "CvsLabel", 0, colon)
  highlight(highlights, row, value_group or "CvsMuted", colon + 1, -1)
end

local function summary_line(counts)
  local parts = {}

  for _, status in ipairs(status_order) do
    local count = counts[status]
    if count and count > 0 then
      parts[#parts + 1] = ("%s: %d"):format(summary_codes[status], count)
    end
  end

  if #parts == 0 then
    return "State Counts: -"
  end

  return ("State Counts: %s"):format(table.concat(parts, ", "))
end

local function append_inline_diff(lines, row_map, highlights, item, inline_diff)
  if not inline_diff or inline_diff.path ~= item.path then
    return
  end

  for _, diff_line in ipairs(inline_diff.lines or {}) do
    local row = #lines + 1
    lines[row] = "   " .. diff_line
    row_map[row] = {
      kind = "file",
      item = item,
    }

    if vim.startswith(diff_line, "@@") then
      highlight(highlights, row, "DiffChange", 3, -1)
    elseif vim.startswith(diff_line, "+") and not vim.startswith(diff_line, "+++") then
      highlight(highlights, row, "DiffAdd", 3, -1)
    elseif vim.startswith(diff_line, "-") and not vim.startswith(diff_line, "---") then
      highlight(highlights, row, "DiffDelete", 3, -1)
    else
      highlight(highlights, row, "CvsMuted", 3, -1)
    end
  end
end

function M.lines(view_state)
  local lines = { "CVS" }
  local row_map = {}
  local highlights = {}
  highlight(highlights, 1, "CvsHeader")

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("Root: %s"):format(view_state.workspace.root_dir)
  highlight_label(highlights, #lines, lines[#lines], "CvsPath")
  lines[#lines + 1] = ("Scope: %s"):format(view_state.scope_label)
  highlight_label(highlights, #lines, lines[#lines])
  lines[#lines + 1] = ("Snapshot: %s%s"):format(
    view_state.generated_at or "-",
    view_state.refreshing and " (refreshing)" or (view_state.cached and " (cached)" or "")
  )
  highlight_label(highlights, #lines, lines[#lines])
  lines[#lines + 1] = ("Files: %d"):format(view_state.total_count or 0)
  highlight_label(highlights, #lines, lines[#lines])
  lines[#lines + 1] = ("Commit selection: %d/%d"):format(
    view_state.selected_count or 0,
    view_state.selectable_count or 0
  )
  highlight_label(highlights, #lines, lines[#lines])

  if view_state.loading then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Loading CVS status..."
    highlight(highlights, #lines, "CvsMuted")
  elseif (view_state.total_count or 0) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Working copy is clean for this scope."
    highlight(highlights, #lines, "CvsMuted")
  else
    lines[#lines + 1] = summary_line(view_state.counts or {})
    highlight_label(highlights, #lines, lines[#lines])

    for _, section in ipairs(view_state.sections or {}) do
      lines[#lines + 1] = ""
      local section_row = #lines + 1
      lines[section_row] = ("%s (%d)"):format(section.title or "Files", #(section.items or {}))
      row_map[section_row] = {
        kind = "section",
        section = section,
      }
      highlight(highlights, section_row, "CvsSection")

      for _, item in ipairs(section.items or {}) do
        local row = #lines + 1
        lines[row] = ("    %s  %s"):format(item.code, item.path)
        row_map[row] = {
          kind = "file",
          item = item,
        }
        highlight(highlights, row, status_highlights[item.status] or "Type", 4, #item.code + 5)
        append_inline_diff(lines, row_map, highlights, item, view_state.inline_diff)
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "<CR> opens the current file"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "o/gO/O/p opens in a split/vsplit/tab/preview"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "dd diffs the current file against its CVS base"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "= toggles the inline diff"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "- toggles the commit selection"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "cc commits the selected files"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "a adds or restores files"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "A adds unknown files as binary (-kb)"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "r schedules the current file for removal"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "R refreshes the status snapshot"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "q closes this buffer"
  highlight(highlights, #lines, "CvsMuted")

  return lines, row_map, highlights
end

return M
