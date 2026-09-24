local M = {}

local function first_message(commit)
  for _, line in ipairs((commit and commit.message) or {}) do
    if line ~= "" then
      return line
    end
  end
  return "(no commit message)"
end

local function action_text(item)
  if item.action == "reverse_merge" then
    local current = item.current_revision and ("; current " .. item.current_revision) or ""
    return ("reverse merge %s -> %s%s"):format(item.revision, item.predecessor, current)
  elseif item.action == "remove" then
    return ("remove file introduced at %s"):format(item.revision)
  elseif item.action == "restore" then
    return ("restore file from %s"):format(item.predecessor)
  end
  return item.action or "unsupported"
end

function M.lines(view_state)
  local lines = { "CVS Revert Plan", "", "Commit: " .. view_state.commit_id }
  local row_map = {}

  if view_state.commit then
    lines[#lines + 1] = "Author: " .. (view_state.commit.author or "?")
    lines[#lines + 1] = "Date:   " .. (view_state.commit.date or "?")
    lines[#lines + 1] = "Message: " .. first_message(view_state.commit)
  end
  lines[#lines + 1] = ""

  if view_state.phase == "loading" then
    lines[#lines + 1] = "Discovering every file in this commit..."
  elseif view_state.phase == "checking" then
    lines[#lines + 1] = "Checking affected files..."
  elseif view_state.error then
    lines[#lines + 1] = "Cannot prepare revert: " .. view_state.error
  else
    local title = view_state.phase == "applied" and "Applied locally" or "Affected files"
    lines[#lines + 1] = title .. (": %d"):format(#(view_state.items or {}))
    for _, item in ipairs(view_state.items or {}) do
      lines[#lines + 1] = ("    %s  %s"):format(item.path, action_text(item))
      row_map[#lines] = item
    end
    if #(view_state.blockers or {}) > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "Blocked"
      for _, blocker in ipairs(view_state.blockers) do
        lines[#lines + 1] = "    " .. blocker
      end
    end
  end

  if #(view_state.messages or {}) > 0 then
    lines[#lines + 1] = ""
    for _, message in ipairs(view_state.messages) do
      lines[#lines + 1] = message
    end
  end

  lines[#lines + 1] = ""
  if view_state.phase == "ready" then
    lines[#lines + 1] = "d reverse diff  R apply locally  cc apply and open commit  yc copy commit ID  q close"
  elseif view_state.phase == "applied" then
    lines[#lines + 1] = "d reverse diff  cc open commit  yc copy commit ID  q close (changes remain)"
  else
    lines[#lines + 1] = "yc copy commit ID  q close"
  end

  return lines, row_map
end

return M
