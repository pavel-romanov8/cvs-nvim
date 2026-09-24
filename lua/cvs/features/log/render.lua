local M = {}

local function change_kind(entry)
  if entry.state == "dead" then
    return "R"
  end
  if require("cvs.features.log.parse").predecessor(entry.revision) == nil then
    return "A"
  end
  return "M"
end

local function scope_lines(view_state)
  local lines = {
    "CVS commit history",
    "Scope: " .. view_state.scope_path,
    "",
  }
  local row_map = {}
  local highlights = {}

  if view_state.loading then
    lines[#lines + 1] = "Loading CVS log..."
  elseif view_state.error then
    lines[#lines + 1] = "CVS log failed: " .. view_state.error
  elseif #view_state.parsed.commits == 0 then
    lines[#lines + 1] = "No commits found."
  else
    lines[#lines + 1] = ("Commits: %d"):format(#view_state.parsed.commits)
    for _, commit in ipairs(view_state.parsed.commits) do
      lines[#lines + 1] = ""
      local id = commit.id or "(no commit ID)"
      lines[#lines + 1] = ("commit %s  %s  %s  %d file%s"):format(
        id,
        commit.date or "?",
        commit.author or "?",
        #commit.files,
        #commit.files == 1 and "" or "s"
      )
      row_map[#lines] = { kind = "commit", commit = commit }
      for _, message in ipairs(commit.message or {}) do
        lines[#lines + 1] = "    " .. message
        row_map[#lines] = { kind = "commit", commit = commit }
      end
      if view_state.expanded and view_state.expanded[commit.key] then
        for _, entry in ipairs(commit.files) do
          lines[#lines + 1] = ("    %s %-8s %s"):format(change_kind(entry), entry.revision, entry.path)
          row_map[#lines] = { kind = "change", commit = commit, entry = entry }
        end
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "= toggle files  d diff file  yc copy commit ID  cr revert commit  R refresh  q close"
  return lines, row_map, highlights, {}
end

function M.lines(view_state)
  if view_state.scope_kind == "directory" then
    return scope_lines(view_state)
  end

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
      if entry.commit_id or entry.lines or #entry.tags > 0 or (entry.branches and entry.branches ~= "") then
        lines[#lines + 1] = ("    %s%s%s%s"):format(
          entry.commit_id and "commit: " .. entry.commit_id or "",
          entry.lines and "  lines: " .. entry.lines or "",
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
  lines[#lines + 1] = "= toggle inline diff  <CR>/d open full diff  yc copy commit ID  cr revert commit  R refresh  q close"
  return lines, row_map, highlights, syntax_rows
end

return M
