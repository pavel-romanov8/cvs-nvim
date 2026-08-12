local config = require("cvs.config")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function invocation_count(path)
  return tonumber(vim.fn.readfile(path)[1])
end

return function()
  local temp_dir = vim.fn.tempname()
  local cvs_dir = temp_dir .. "/CVS"
  local target = temp_dir .. "/file.lua"
  local fake_cvs = temp_dir .. "/fake-cvs"
  local count_file = temp_dir .. "/count"

  vim.fn.mkdir(cvs_dir, "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, cvs_dir .. "/Root")
  vim.fn.writefile({ "module" }, cvs_dir .. "/Repository")
  vim.fn.writefile({ "/file.lua/1.7/Thu Jan 01 00:00:00 2026//" }, cvs_dir .. "/Entries")
  vim.fn.writefile({ "working content" }, target)
  vim.fn.writefile({
    "#!/bin/sh",
    ("count_file=%s"):format(vim.fn.shellescape(count_file)),
    "count=0",
    'if [ -f "$count_file" ]; then count=$(command cat "$count_file"); fi',
    "count=$((count + 1))",
    'printf "%s\\n" "$count" > "$count_file"',
    'printf "M file.lua\\n"',
  }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")

  state.status_cache = {}
  config.setup({
    cvs = {
      bin = fake_cvs,
    },
    notifications = {
      enabled = false,
    },
  })
  service.setup()

  local first = service.collect({ path = temp_dir })
  assert_eq(first.cached, false, "first status is fresh")
  assert_eq(invocation_count(count_file), 1, "first status invokes CVS")

  local second = service.collect({ path = temp_dir })
  assert_eq(second.cached, true, "second status uses the cache")
  assert_eq(invocation_count(count_file), 1, "cached status does not invoke CVS")
  assert_eq(state.get_snapshot(temp_dir).cached, true, "cache hits update the latest workspace snapshot")

  local forced = service.collect({ path = temp_dir, force = true })
  assert_eq(forced.cached, false, "forced status is fresh")
  assert_eq(invocation_count(count_file), 2, "forced status invokes CVS")

  vim.fn.delete(target)
  vim.fn.writefile({
    "#!/bin/sh",
    ("count_file=%s"):format(vim.fn.shellescape(count_file)),
    "count=$(command cat \"$count_file\")",
    "count=$((count + 1))",
    'printf "%s\\n" "$count" > "$count_file"',
    'printf "U file.lua\\n"',
  }, fake_cvs)
  local missing = service.collect({ path = temp_dir, force = true })
  assert_eq(missing.files[1].code, "!", "locally deleted tracked file gets a missing marker")
  assert_eq(missing.files[1].status, "missing", "locally deleted tracked file is visible as missing")
  vim.fn.writefile({ "working content" }, target)
  vim.fn.writefile({
    "#!/bin/sh",
    ("count_file=%s"):format(vim.fn.shellescape(count_file)),
    "count=$(command cat \"$count_file\")",
    "count=$((count + 1))",
    'printf "%s\\n" "$count" > "$count_file"',
    'printf "M file.lua\\n"',
  }, fake_cvs)

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, target)
  vim.api.nvim_exec_autocmds("BufWritePost", {
    buffer = bufnr,
    modeline = false,
  })

  local after_write = service.collect({ path = temp_dir })
  assert_eq(after_write.cached, false, "writing a working file invalidates the cache")
  assert_eq(invocation_count(count_file), 4, "status after a write invokes CVS")

  service.collect({ path = target, force = true })
  assert_eq(invocation_count(count_file), 5, "file-scoped force invokes CVS")
  local workspace_after_file = service.collect({ path = temp_dir })
  assert_eq(workspace_after_file.cached, false, "forcing one scope invalidates overlapping scopes")
  assert_eq(invocation_count(count_file), 6, "invalidated workspace scope invokes CVS")

  service.collect({ path = temp_dir, files = { "file.lua" } })
  assert_eq(invocation_count(count_file), 7, "file list has a distinct cache key")
  local same_files = service.collect({ path = temp_dir, files = { "file.lua" } })
  assert_eq(same_files.cached, true, "identical file list uses its cache")
  assert_eq(invocation_count(count_file), 7, "cached file list does not invoke CVS")
  service.collect({ path = temp_dir, files = { "other.lua" } })
  assert_eq(invocation_count(count_file), 8, "different file lists do not share cache entries")

  config.get().status.cache.ttl_ms = 0
  service.collect({ path = temp_dir })
  service.collect({ path = temp_dir })
  assert_eq(invocation_count(count_file), 10, "zero TTL disables cache reuse")

  config.get().status.cache.ttl_ms = 300000
  config.get().status.cache.enabled = false
  service.collect({ path = temp_dir })
  assert_eq(invocation_count(count_file), 11, "disabled cache invokes CVS")
  config.get().status.cache.enabled = true
  local after_reenable = service.collect({ path = temp_dir })
  assert_eq(after_reenable.cached, false, "disabled cache does not preserve an older entry")
  assert_eq(invocation_count(count_file), 12, "reenabling starts with a fresh status")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  state.status_cache = {}
  config.setup()
  vim.fn.delete(temp_dir, "rf")
end
