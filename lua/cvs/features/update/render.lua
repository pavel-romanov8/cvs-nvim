local types = require("cvs.core.types")
local ui_render = require("cvs.ui.render")

local M = {}

local order = {
  types.status.updated,
  types.status.patched,
  types.status.modified,
  types.status.added,
  types.status.removed,
  types.status.conflict,
  types.status.unknown,
}

local labels = {
  [types.status.updated] = "Updated",
  [types.status.patched] = "Patched",
  [types.status.modified] = "Modified",
  [types.status.added] = "Added",
  [types.status.removed] = "Removed",
  [types.status.conflict] = "Conflicts",
  [types.status.unknown] = "Unknown",
}

local function phase_label(state)
  if state.phase == "queued" then
    return "Queued"
  end

  if state.phase == "running" then
    return "Running"
  end

  return "Completed"
end

local function append_summary(lines, summary)
  local items = {}

  for _, status in ipairs(order) do
    local count = summary[status]
    if count and count > 0 then
      items[#items + 1] = { labels[status], tostring(count) }
    end
  end

  if #items == 0 then
    items[1] = { "Changes", "0" }
  end

  ui_render.key_values(lines, items)
end

local function append_items(lines, items)
  if not items or #items == 0 then
    lines[#lines + 1] = "No file updates were parsed."
    return
  end

  for _, item in ipairs(items) do
    lines[#lines + 1] = ("%s  %s"):format(item.code, item.path)
  end
end

local function append_messages(lines, messages)
  if not messages or #messages == 0 then
    return
  end

  ui_render.section(lines, "Messages")
  vim.list_extend(lines, messages)
end

function M.lines(state)
  local lines = { "CVS Update" }

  ui_render.section(lines, "Run")
  ui_render.key_values(lines, {
    { "Phase", phase_label(state) },
    { "Workspace", state.workspace.root_dir },
    { "Scope", state.scope_label or "workspace" },
    { "Started At", state.started_at or "-" },
    { "Completed At", state.completed_at or "-" },
  })

  ui_render.section(lines, "Command")
  lines[#lines + 1] = table.concat(state.command, " ")

  if state.result then
    lines[#lines + 1] = ("exit code: %s"):format(state.result.code)
    lines[#lines + 1] = ("duration: %d ms"):format(state.result.duration_ms)
  end

  if state.phase ~= "done" then
    ui_render.section(lines, "Progress")
    if state.phase == "queued" then
      lines[#lines + 1] = "Waiting for another mutating CVS operation to finish."
    else
      lines[#lines + 1] = "Running `cvs update`..."
    end
  end

  if state.parsed then
    ui_render.section(lines, "Summary")
    append_summary(lines, state.parsed.summary or {})

    ui_render.section(lines, "Files")
    append_items(lines, state.parsed.items or {})

    if state.parsed.has_conflicts then
      ui_render.section(lines, "Conflicts")
      lines[#lines + 1] = "Conflicts were detected. Inspect the affected files or run :CvsConflicts."
    end
  end

  append_messages(lines, state.messages)

  lines[#lines + 1] = ""
  lines[#lines + 1] = "q closes this buffer"

  return lines
end

return M
