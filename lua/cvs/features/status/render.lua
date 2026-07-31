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
    view_state.cached and " (cached)" or ""
  )
  highlight_label(highlights, #lines, lines[#lines])
  lines[#lines + 1] = ("Files: %d"):format(view_state.total_count or 0)
  highlight_label(highlights, #lines, lines[#lines])

  if (view_state.total_count or 0) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Working copy is clean for this scope."
    highlight(highlights, #lines, "CvsMuted")
  else
    lines[#lines + 1] = summary_line(view_state.counts or {})
    highlight_label(highlights, #lines, lines[#lines])

    for _, section in ipairs(view_state.sections or {}) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("%s (%d)"):format(section.title or "Files", #(section.items or {}))
      highlight(highlights, #lines, "CvsSection")

      for _, item in ipairs(section.items or {}) do
        local row = #lines + 1
        lines[row] = ("%s  %s"):format(item.code, item.path)
        row_map[row] = item
        highlight(highlights, row, status_highlights[item.status] or "Type", 0, #item.code + 1)
      end
    end
  end

  if view_state.messages and #view_state.messages > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Messages"
    highlight(highlights, #lines, "CvsSection")
    for _, message in ipairs(view_state.messages) do
      lines[#lines + 1] = message
      highlight(highlights, #lines, "CvsMuted")
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "<CR> opens the current file"
  highlight(highlights, #lines, "CvsMuted")
  lines[#lines + 1] = "a adds or restores the current file"
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
