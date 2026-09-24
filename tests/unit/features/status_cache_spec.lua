local config = require("cvs.config")
local service = require("cvs.features.status.service")
local state = require("cvs.core.state")

local function count(path)
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
    'printf "%s\\n" "$((count + 1))" > "$count_file"',
    'printf "M file.lua\\n"',
  }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")

  state.status_cache = {}
  config.setup({ cvs = { bin = fake_cvs }, notifications = { enabled = false } })
  service.setup()

  local first = service.collect({ path = temp_dir })
  local cached = service.collect({ path = temp_dir })
  assert(not first.cached and cached.cached and count(count_file) == 1,
    "identical status reads reuse a fresh snapshot")

  local forced = service.collect({ path = temp_dir, force = true })
  assert(not forced.cached and count(count_file) == 2, "force bypasses and replaces the cache")

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, target)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr, modeline = false })
  assert(not service.collect({ path = temp_dir }).cached and count(count_file) == 3,
    "writing a working file invalidates workspace status")

  service.collect({ path = temp_dir, files = { "file.lua" } })
  local same_scope = service.collect({ path = temp_dir, files = { "file.lua" } })
  service.collect({ path = temp_dir, files = { "other.lua" } })
  assert(same_scope.cached and count(count_file) == 5,
    "targeted file sets have stable, distinct cache keys")

  config.get().status.cache.enabled = false
  service.collect({ path = temp_dir })
  service.collect({ path = temp_dir })
  assert(count(count_file) == 7, "disabled cache always queries CVS")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  state.status_cache = {}
  config.setup()
  vim.fn.delete(temp_dir, "rf")
end
