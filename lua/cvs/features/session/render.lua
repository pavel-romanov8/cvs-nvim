local M = {}

local section_order = {
  outgoing = 1,
  attention = 2,
  incoming = 3,
}

local section_titles = {
  outgoing = "Selected Changes",
  attention = "Needs Action",
  incoming = "Incoming Changes",
}

local detail_labels = {
  added = "added to CVS; ready to commit",
  removed = "scheduled for removal",
  conflict = "resolve the conflict before committing",
  unknown = "press a to add this file",
  updated = "update before you commit related work",
  patched = "update before you commit related work",
}

local function comment(text)
  return "# " .. text
end

local function status_label(item)
  local selected = item.selectable and (item.selected and "x" or " ") or "-"
  local line = ("[%s] %s %s"):format(selected, item.code, item.path)
  local detail = item.detail or detail_labels[item.status]
  if detail and detail ~= "" then
    line = line .. " -- " .. detail
  end

  return line
end

local function section_sorter(left, right)
  local left_index = section_order[left.kind] or 99
  local right_index = section_order[right.kind] or 99
  if left_index ~= right_index then
    return left_index < right_index
  end

  return (left.title or "") < (right.title or "")
end

function M.lines(view_state)
  local lines = vim.deepcopy(view_state.message_lines or { "" })
  local row_map = {}
  if #lines == 0 then
    lines = { "" }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = comment("Write the CVS commit message above.")
  lines[#lines + 1] = comment("Submit with :write or <C-c><C-c>.")
  lines[#lines + 1] = comment("Toggle files with <space>; use a to add, r to remove, <CR> to open, R to refresh.")
  lines[#lines + 1] = comment(("Workspace: %s"):format(view_state.workspace.root_dir))
  lines[#lines + 1] = comment(("Scope: %s"):format(view_state.scope_label))
  lines[#lines + 1] = comment(("Phase: %s"):format(view_state.phase))
  lines[#lines + 1] = comment(("Selected: %d/%d"):format(view_state.selected_count or 0, view_state.selectable_count or 0))

  if view_state.generated_at then
    lines[#lines + 1] = comment(("Snapshot: %s"):format(view_state.generated_at))
  end

  if view_state.started_at then
    lines[#lines + 1] = comment(("Started At: %s"):format(view_state.started_at))
  end

  if view_state.completed_at then
    lines[#lines + 1] = comment(("Completed At: %s"):format(view_state.completed_at))
  end

  if view_state.command then
    lines[#lines + 1] = comment(("Command: %s"):format(table.concat(view_state.command, " ")))
  end

  if view_state.messages and #view_state.messages > 0 then
    lines[#lines + 1] = comment("Messages:")
    for _, message in ipairs(view_state.messages) do
      lines[#lines + 1] = comment("  " .. message)
    end
  end

  local sections = vim.deepcopy(view_state.sections or {})
  table.sort(sections, section_sorter)

  for _, section in ipairs(sections) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = comment(section.title or section_titles[section.kind] or "Files")

    if not section.items or #section.items == 0 then
      lines[#lines + 1] = comment("  nothing to show")
    else
      for _, item in ipairs(section.items) do
        local row = #lines + 1
        lines[row] = comment(status_label(item))
        row_map[row] = item
      end
    end
  end

  return lines, row_map
end

return M
