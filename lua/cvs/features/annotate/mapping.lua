local M = {}

local function diff_text(lines)
  return #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
end

local function local_entry(text)
  return {
    local_change = true,
    text = text,
  }
end

function M.entries(baseline, current_lines)
  baseline = baseline or {}
  current_lines = current_lines or {}

  if #baseline == 0 then
    if #current_lines == 0 or (#current_lines == 1 and current_lines[1] == "") then
      return {}, false
    end

    local mapped = {}
    for index, text in ipairs(current_lines) do
      mapped[index] = local_entry(text)
    end
    return mapped, true
  end

  local baseline_lines = {}
  for index, entry in ipairs(baseline) do
    baseline_lines[index] = entry.text or ""
  end

  if #current_lines == 1
    and current_lines[1] == ""
    and not (#baseline_lines == 1 and baseline_lines[1] == "")
  then
    current_lines = {}
  end

  local hunks = vim.diff(diff_text(baseline_lines), diff_text(current_lines), {
    algorithm = "histogram",
    result_type = "indices",
  })
  if #hunks == 0 then
    return baseline, false
  end

  local mapped = {}
  local baseline_index = 1
  local current_index = 1

  for _, hunk in ipairs(hunks) do
    local baseline_start, baseline_count, current_start, current_count = unpack(hunk)
    local baseline_change = baseline_count == 0 and baseline_start + 1 or baseline_start
    local current_change = current_count == 0 and current_start + 1 or current_start

    while baseline_index < baseline_change and current_index < current_change do
      mapped[current_index] = baseline[baseline_index]
      baseline_index = baseline_index + 1
      current_index = current_index + 1
    end

    for index = current_change, current_change + current_count - 1 do
      mapped[index] = local_entry(current_lines[index])
    end

    baseline_index = baseline_change + baseline_count
    current_index = current_change + current_count
  end

  while baseline_index <= #baseline and current_index <= #current_lines do
    mapped[current_index] = baseline[baseline_index]
    baseline_index = baseline_index + 1
    current_index = current_index + 1
  end

  return mapped, true
end

return M
