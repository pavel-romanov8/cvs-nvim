local M = {}

local function trim(value)
  return vim.trim(value or "")
end

-- CVS log separates revisions with a line of dashes and files with equals.
function M.parse(lines)
  local result = { entries = {}, symbols = {}, header = {}, messages = {} }
  local entry
  local in_symbols = false
  local in_description = false

  for _, line in ipairs(lines or {}) do
    if line:match("^=+$") then
      break
    elseif line:match("^%-+$") and #line >= 20 then
      entry = nil
    elseif line:match("^revision%s+[%d.]+%s*$") then
      local revision = line:match("^revision%s+([%d.]+)")
      entry = { revision = revision, message = {}, tags = {} }
      result.entries[#result.entries + 1] = entry
      in_symbols = false
      in_description = false
    elseif entry then
      local continuation_commit_id = entry.date and line:match("commitid:%s*([^;]+)")
      if continuation_commit_id then
        entry.commit_id = trim(continuation_commit_id)
      elseif line:match("^branches:%s*") then
        entry.branches = trim(line:match("^branches:%s*(.*)"))
      elseif not entry.date then
        local date, author, state = line:match("^date:%s*(.-);%s*author:%s*(.-);%s*state:%s*([^;]+)")
        if date then
          entry.date = trim(date)
          entry.author = trim(author)
          entry.state = trim(state)
          entry.lines = line:match("lines:%s*([^;]+)")
          entry.branches = line:match("branches:%s*([^;]+)")
          entry.commit_id = trim(line:match("commitid:%s*([^;]+)"))
          if entry.commit_id == "" then
            entry.commit_id = nil
          end
        else
          entry.message[#entry.message + 1] = line
        end
      else
        entry.message[#entry.message + 1] = line
      end
    elseif in_symbols then
      local name, revision = line:match("^%s+([^:%s]+):%s*([%d.]+)%s*$")
      if name then
        result.symbols[#result.symbols + 1] = { name = name, revision = revision }
      else
        in_symbols = false
      end
    elseif line:match("^symbolic names:%s*$") then
      in_symbols = true
    elseif line:match("^description:%s*$") then
      in_description = true
    elseif not in_description then
      local key, value = line:match("^([^:]+):%s*(.*)$")
      if key then
        result.header[trim(key)] = trim(value)
      end
    end
  end

  for _, item in ipairs(result.symbols) do
    for _, revision in ipairs(result.entries) do
      if item.revision == revision.revision then
        revision.tags[#revision.tags + 1] = item.name
      else
        -- CVS represents a branch symbol using a zero penultimate component
        -- (e.g. 1.2.0.2); branch revisions use 1.2.2.N.
        local branch = item.revision:match("^(.*)%.0%.(%d+)$")
        local number = item.revision:match("^.*%.0%.(%d+)$")
        if branch and vim.startswith(revision.revision, branch .. "." .. number .. ".") then
          revision.tags[#revision.tags + 1] = item.name .. " (branch)"
        end
      end
    end
  end

  for _, revision in ipairs(result.entries) do
    while #revision.message > 0 and revision.message[#revision.message] == "" do
      table.remove(revision.message)
    end
  end

  return result
end

local function finish_section(files, section, opts)
  if not section or #section.lines == 0 then
    return
  end

  local parsed = M.parse(section.lines)
  local working = parsed.header["Working file"]
  if not working or working == "" then
    return
  end

  local logging_dir = section.logging_dir
  local logging_prefix = opts and opts.logging_prefix
  local rcs_file = parsed.header["RCS file"]
  local repository_relative
  if logging_prefix and rcs_file then
    local archive = rcs_file:gsub(",v$", ""):gsub("/Attic/", "/")
    local needle = "/" .. logging_prefix .. "/"
    local start = archive:find(needle, 1, true)
    if start then
      repository_relative = archive:sub(start + #needle)
    elseif vim.startswith(archive, logging_prefix .. "/") then
      repository_relative = archive:sub(#logging_prefix + 2)
    end
  end
  if logging_prefix and logging_dir then
    if logging_dir == logging_prefix then
      logging_dir = "."
    elseif vim.startswith(logging_dir, logging_prefix .. "/") then
      logging_dir = logging_dir:sub(#logging_prefix + 2)
    end
  end
  local relative = repository_relative or working
  if not repository_relative and logging_dir and logging_dir ~= "." and logging_dir ~= "" then
    local prefix = logging_dir .. "/"
    if not vim.startswith(relative, prefix) then
      relative = prefix .. relative
    end
  end
  relative = vim.fs.normalize(relative)

  local absolute = relative
  if opts and opts.scope_path then
    absolute = vim.fs.normalize(opts.scope_path .. "/" .. relative)
  end

  for _, entry in ipairs(parsed.entries) do
    entry.path = relative
    entry.absolute_path = absolute
  end

  files[#files + 1] = {
    path = relative,
    absolute_path = absolute,
    parsed = parsed,
  }
end

-- Parse recursive `cvs log` output and group file revisions by the shared
-- commitid emitted by modern CVS servers. Entries without a commitid remain
-- separate; guessing changesets from timestamps or messages would be unsafe.
function M.parse_scope(lines, opts)
  opts = opts or {}
  local files = {}
  local logging_dir = "."
  local section

  for _, line in ipairs(lines or {}) do
    local next_logging_dir = line:match("^cvs%s+r?log:%s+Logging%s+(.+)$")
      or line:match("^cvs%s+%[[^]]+%]%s+r?log:%s+Logging%s+(.+)$")
    if next_logging_dir then
      if section then
        finish_section(files, section, opts)
        section = nil
      end
      logging_dir = trim(next_logging_dir)
    elseif line:match("^RCS file:%s*") then
      if section then
        finish_section(files, section, opts)
      end
      section = { logging_dir = logging_dir, lines = { line } }
    elseif section then
      section.lines[#section.lines + 1] = line
      if line:match("^=+$") then
        finish_section(files, section, opts)
        section = nil
      end
    end
  end
  finish_section(files, section, opts)

  local commits_by_key = {}
  local commits = {}
  for _, file in ipairs(files) do
    for _, entry in ipairs(file.parsed.entries) do
      local key = entry.commit_id or (file.path .. "@" .. entry.revision)
      local commit = commits_by_key[key]
      if not commit then
        commit = {
          id = entry.commit_id,
          key = key,
          date = entry.date,
          author = entry.author,
          message = vim.deepcopy(entry.message or {}),
          files = {},
        }
        commits_by_key[key] = commit
        commits[#commits + 1] = commit
      end
      commit.files[#commit.files + 1] = entry
    end
  end

  table.sort(commits, function(left, right)
    local left_date = left.date or ""
    local right_date = right.date or ""
    if left_date == right_date then
      return left.key > right.key
    end
    return left_date > right_date
  end)
  for _, commit in ipairs(commits) do
    table.sort(commit.files, function(left, right)
      return (left.path or "") < (right.path or "")
    end)
  end

  return { files = files, commits = commits }
end

function M.find_commit(parsed, commit_id)
  for _, commit in ipairs((parsed and parsed.commits) or {}) do
    if commit.id == commit_id then
      return commit
    end
  end
  return nil
end

-- CVS branch revisions end in their own sequence number. The first commit
-- on a branch has the branch point as its predecessor.
function M.predecessor(revision)
  local parts = vim.split(revision or "", ".", { plain = true })
  if #parts < 2 then
    return nil
  end
  local last = tonumber(parts[#parts])
  if not last then
    return nil
  end
  if last > 1 then
    parts[#parts] = tostring(last - 1)
  elseif #parts > 2 then
    table.remove(parts)
    table.remove(parts)
  else
    return nil
  end
  return table.concat(parts, ".")
end

return M
