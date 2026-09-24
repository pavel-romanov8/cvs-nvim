local M = {}

-- Parse the two sides of each hunk independently: deleted text belongs to
-- the old revision, added text to the new one, and context appears in both.
-- Offsets returned here refer to the text *after* the diff prefix.
local function hunks(lines, max_lines, max_bytes)
  local result = {}
  local current
  local bytes = 0
  for row = 1, math.min(#lines, max_lines) do
    local line = lines[row]
    bytes = bytes + #line
    if bytes > max_bytes then break end
    if line:match("^@@ ") then
      if #result >= 32 then break end -- avoid thousands of tiny parsers
      current = { old = { lines = {}, rows = {} }, new = { lines = {}, rows = {} } }
      result[#result + 1] = current
    elseif current then
      local prefix = line:sub(1, 1)
      if prefix == " " or prefix == "-" or prefix == "+" then
        local function add(side)
          side.lines[#side.lines + 1] = line:sub(2)
          side.rows[#side.rows + 1] = row
        end
        if prefix ~= "+" then add(current.old) end
        if prefix ~= "-" then add(current.new) end
      end
    end
  end
  return result
end

local function captures_for_side(side, lang, query, output, diff_lines, deleted_only)
  if #side.lines == 0 then return end
  local source = table.concat(side.lines, "\n") .. "\n"
  local parser = vim.treesitter.get_string_parser(source, lang)
  for _, tree in ipairs(parser:parse()) do
    for id, node, metadata in query:iter_captures(tree:root(), source, 0, -1) do
      if #output >= 8000 then return end
      local capture = query.captures[id]
      local start_row, start_col, end_row, end_col = node:range()
      if metadata and metadata.range then
        start_row, start_col, end_row, end_col = unpack(metadata.range)
      end
      for row = start_row, math.min(end_row, #side.rows - 1) do
        local line = side.lines[row + 1]
        local first = row == start_row and start_col or 0
        local last = row == end_row and end_col or #line
        last = math.min(last, #line)
        if last > first and (not deleted_only or diff_lines[side.rows[row + 1]]:sub(1, 1) == "-") then
          output[#output + 1] = {
            row = side.rows[row + 1],
            start_col = first,
            end_col = last,
            capture = capture,
            lang = lang,
            priority = tonumber(metadata and metadata.priority) or 100,
          }
        end
      end
    end
  end
end

function M.captures(lines, path, opts)
  opts = opts or {}
  if not vim.treesitter or not vim.treesitter.get_string_parser then return {} end
  local filetype = vim.filetype.match({ filename = path })
  local lang = filetype and vim.treesitter.language.get_lang(filetype)
  if not lang then return {} end
  local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not query then return {} end
  local output = {}
  for _, hunk in ipairs(hunks(lines, opts.max_lines or 1000, opts.max_bytes or 262144)) do
    -- Keep old-side context for parsing but color it only once, from the new
    -- side. Deleted lines still receive their old-side syntax colors.
    local old_ok = pcall(captures_for_side, hunk.old, lang, query, output, lines, true)
    local new_ok = pcall(captures_for_side, hunk.new, lang, query, output, lines, false)
    if not old_ok or not new_ok then return {} end
    if #output >= 8000 then break end
  end
  return output
end

local groups = {}
local function foreground_group(capture, lang)
  local key = capture .. "." .. lang
  if groups[key] then return groups[key] end
  local hl = vim.api.nvim_get_hl(0, { name = "@" .. key, link = false })
  if not hl.fg and not hl.ctermfg then
    hl = vim.api.nvim_get_hl(0, { name = "@" .. capture, link = false })
  end
  if not hl.fg and not hl.ctermfg then return nil end
  local name = "CvsLogSyntax" .. key:gsub("[^%w]", "_")
  vim.api.nvim_set_hl(0, name, {
    fg = hl.fg, ctermfg = hl.ctermfg, bold = hl.bold, italic = hl.italic,
    underline = hl.underline, undercurl = hl.undercurl,
  })
  groups[key] = name
  return name
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("CvsLogSyntax", { clear = true }),
  callback = function()
    local previous = vim.tbl_keys(groups)
    groups = {}
    vim.schedule(function()
      for _, key in ipairs(previous) do
        local capture, lang = key:match("^(.*)%.([^%.]+)$")
        if capture then foreground_group(capture, lang) end
      end
    end)
  end,
})

-- row_map maps 1-based diff rows to 1-based destination rows; prefix includes
-- both the UI indentation and the +/-/space marker.
function M.apply(bufnr, namespace, tokens, row_map, prefix)
  for _, token in ipairs(tokens or {}) do
    local row = type(row_map) == "function" and row_map(token.row) or row_map[token.row]
    local group = row and foreground_group(token.capture, token.lang)
    if group then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row - 1, prefix + token.start_col, {
        end_col = prefix + token.end_col,
        hl_group = group,
        hl_mode = "combine",
        priority = 200 + token.priority,
      })
    end
  end
end

M._hunks = hunks
return M
