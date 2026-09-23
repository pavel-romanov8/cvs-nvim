local M = {}

function M.lines(view_state)
  local lines = {
    "CVS file history",
    "File: " .. view_state.target_path,
    "",
  }
  local row_map = {}

  if view_state.loading then
    lines[#lines + 1] = "Loading CVS log..."
  elseif view_state.error then
    lines[#lines + 1] = "CVS log failed: " .. view_state.error
  elseif #view_state.parsed.entries == 0 then
    lines[#lines + 1] = "No revisions found."
  else
    local header = view_state.parsed.header
    if header["head"] then
      lines[#lines + 1] = "Head: " .. header["head"]
    end
    if header["branch"] and header["branch"] ~= "" then
      lines[#lines + 1] = "Branch: " .. header["branch"]
    end
    lines[#lines + 1] = ("Revisions: %d"):format(#view_state.parsed.entries)

    for _, entry in ipairs(view_state.parsed.entries) do
      lines[#lines + 1] = ""
      local line = ("revision %s  %s  %s  %s"):format(
        entry.revision,
        entry.date or "?",
        entry.author or "?",
        entry.state or "?"
      )
      lines[#lines + 1] = line
      row_map[#lines] = entry
      if entry.lines or #entry.tags > 0 or (entry.branches and entry.branches ~= "") then
        lines[#lines + 1] = ("    %s%s%s"):format(
          entry.lines and "lines: " .. entry.lines or "",
          #entry.tags > 0 and "  tags: " .. table.concat(entry.tags, ", ") or "",
          entry.branches and entry.branches ~= "" and "  branches: " .. entry.branches or ""
        )
        row_map[#lines] = entry
      end
      for _, message in ipairs(entry.message) do
        lines[#lines + 1] = "    " .. message
        row_map[#lines] = entry
      end
      local inline = view_state.inline
      if inline and inline.revision == entry.revision then
        local preview = {}
        if inline.loading then
          preview = { "Loading revision contents..." }
        elseif inline.error then
          preview = { "Could not load revision: " .. inline.error }
        elseif #inline.lines == 0 then
          preview = { "(empty file)" }
        else
          preview = inline.lines
        end
        for _, content in ipairs(preview) do
          lines[#lines + 1] = "    | " .. content
          row_map[#lines] = entry
        end
        if inline.truncated then
          lines[#lines + 1] = "    | ... (preview truncated; press <CR> for full revision)"
          row_map[#lines] = entry
        end
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "= toggle revision contents  <CR> open full revision  d diff  R refresh  q close"
  return lines, row_map
end

return M
