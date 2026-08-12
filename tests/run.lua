local root = vim.fn.getcwd()

local tests = {
  "tests/unit/core_util_spec.lua",
  "tests/unit/commands_spec.lua",
  "tests/unit/cvs_cmd_spec.lua",
  "tests/unit/cvs_entries_spec.lua",
  "tests/unit/features/annotate_parse_spec.lua",
  "tests/unit/features/annotate_mapping_spec.lua",
  "tests/unit/features/annotate_render_spec.lua",
  "tests/unit/features/annotate_service_spec.lua",
  "tests/unit/features/commit_buffer_spec.lua",
  "tests/unit/features/commit_service_spec.lua",
  "tests/unit/features/diff_service_spec.lua",
  "tests/unit/features/diff_parse_spec.lua",
  "tests/unit/features/diff_sides_spec.lua",
  "tests/unit/features/files_service_spec.lua",
  "tests/unit/features/status_render_spec.lua",
  "tests/unit/features/status_service_spec.lua",
  "tests/unit/features/status_cache_spec.lua",
  "tests/unit/features/session_buffer_spec.lua",
  "tests/unit/features/session_service_spec.lua",
  "tests/ui/annotate_buffer_spec.lua",
  "tests/ui/diff_full_view_spec.lua",
  "tests/ui/diff_view_spec.lua",
  "tests/ui/status_buffer_spec.lua",
  "tests/ui/status_async_spec.lua",
  "tests/unit/features/update_parse_spec.lua",
  "tests/unit/features/update_render_spec.lua",
}

local failures = {}

for _, path in ipairs(tests) do
  local ok, loaded = pcall(dofile, root .. "/" .. path)
  if not ok then
    failures[#failures + 1] = ("%s: load error: %s"):format(path, loaded)
  else
    local ok_run, err = pcall(loaded, root)
    if not ok_run then
      failures[#failures + 1] = ("%s: %s"):format(path, err)
    end
  end
end

if #failures > 0 then
  for _, failure in ipairs(failures) do
    print(failure)
  end
  vim.cmd("cq")
else
  print(("ok - %d tests"):format(#tests))
  vim.cmd("qall!")
end
