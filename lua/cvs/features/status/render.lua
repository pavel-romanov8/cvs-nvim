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

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("Root: %s"):format(view_state.workspace.root_dir)
  lines[#lines + 1] = ("Scope: %s"):format(view_state.scope_label)
  lines[#lines + 1] = ("Snapshot: %s"):format(view_state.generated_at or "-")
  lines[#lines + 1] = ("Files: %d"):format(view_state.total_count or 0)

  if (view_state.total_count or 0) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Working copy is clean for this scope."
  else
    lines[#lines + 1] = summary_line(view_state.counts or {})

    for _, section in ipairs(view_state.sections or {}) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("%s (%d)"):format(section.title or "Files", #(section.items or {}))

      for _, item in ipairs(section.items or {}) do
        local row = #lines + 1
        lines[row] = ("%s  %s"):format(item.code, item.path)
        row_map[row] = item
      end
    end
  end

  if view_state.messages and #view_state.messages > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Messages"
    vim.list_extend(lines, view_state.messages)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "<CR> opens the current file"
  lines[#lines + 1] = "a adds or restores the current file"
  lines[#lines + 1] = "r schedules the current file for removal"
  lines[#lines + 1] = "R refreshes the status snapshot"
  lines[#lines + 1] = "q closes this buffer"

  return lines, row_map
end

return M
