local M = {}

function M.lines(view_state)
  local lines = {
    "CVS file history",
    "File: " .. view_state.target_path,
    "",
  }
  local row_map = {}
  local highlights = {}
  local syntax_rows = {}

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
          preview = { "Loading revision diff..." }
        elseif inline.error then
          preview = { "Could not load diff: " .. inline.error }
        elseif #inline.lines == 0 and #(inline.messages or {}) == 0 then
          preview = { "No differences." }
        else
          preview = inline.lines
        end
        for index, content in ipairs(preview) do
          lines[#lines + 1] = "    | " .. content
          row_map[#lines] = entry
          if not inline.loading and not inline.error then
            syntax_rows[index] = #lines
          end
          local group
          if content:match("^@@") then
            group = "CvsDiffChange"
          elseif content:match("^%+") then
            group = "CvsDiffAdd"
          elseif content:match("^%-") then
            group = "CvsDiffDelete"
          elseif not inline.loading and not inline.error then
            group = "CvsMuted"
          end
          if group then
            highlights[#highlights + 1] = { row = #lines, group = group }
          end
        end
        for _, message in ipairs(inline.messages or {}) do
          lines[#lines + 1] = "    | " .. message
          row_map[#lines] = entry
          highlights[#highlights + 1] = { row = #lines, group = "CvsMuted" }
        end
        if inline.truncated then
          lines[#lines + 1] = "    | ... (diff truncated; press <CR> for full view)"
          row_map[#lines] = entry
          highlights[#highlights + 1] = { row = #lines, group = "WarningMsg" }
        end
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "= toggle inline diff  <CR>/d open full diff  R refresh  q close"
  return lines, row_map, highlights, syntax_rows
end

return M
