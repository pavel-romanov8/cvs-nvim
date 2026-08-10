local config = require("cvs.config")
local runner = require("cvs.cvs.runner")
local service = require("cvs.features.diff.service")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local temp_dir = vim.fn.tempname()
  local cvs_dir = temp_dir .. "/CVS"
  local target = temp_dir .. "/file.lua"
  local fake_cvs = temp_dir .. "/fake-cvs"

  vim.fn.mkdir(cvs_dir, "p")
  vim.fn.writefile({ ":local:/tmp/repository" }, cvs_dir .. "/Root")
  vim.fn.writefile({ "module" }, cvs_dir .. "/Repository")
  vim.fn.writefile({ "/file.lua/1.7/Thu Jan 01 00:00:00 2026//" }, cvs_dir .. "/Entries")
  vim.fn.writefile({ "working content" }, target)
  vim.fn.writefile({
    "#!/bin/sh",
    "printf '%s\\n' 'Index: file.lua' '--- file.lua' '+++ file.lua' '@@ -1 +1 @@' '-base content' '+working content'",
    "exit 1",
  }, fake_cvs)
  vim.fn.setfperm(fake_cvs, "rwx------")

  config.setup({
    cvs = {
      bin = fake_cvs,
    },
    notifications = {
      enabled = false,
    },
  })

  local view_state, err = service._prepare({ path = target })
  assert_eq(err, nil, "tracked file prepares without an error")
  assert_eq(view_state.target_path, target, "diff resolves the target path")
  assert_eq(view_state.revision, "1.7", "diff uses the checked-out revision")
  assert_eq(view_state.request.cwd, temp_dir, "CVS base command runs beside the file")
  assert_eq(
    table.concat(view_state.command, " "),
    fake_cvs .. " -Q update -p -r 1.7 file.lua",
    "plain diff prints the checked-out file revision"
  )
  local stream_state = service._prepare({ path = target, stream = true })
  assert_eq(table.concat(stream_state.command, " "), fake_cvs .. " diff -u file.lua", "streamed diff requests unified hunks")

  local collected
  local collect_err
  local process = service.collect({ path = target }, function(result, result_err)
    collected = result
    collect_err = result_err
  end)
  assert_eq(process ~= nil, true, "streamed diff returns its process")
  assert_eq(vim.wait(1000, function()
    return collected ~= nil or collect_err ~= nil
  end, 10), true, "streamed diff completes")
  assert_eq(collect_err, nil, "CVS diff exit code one is successful")
  assert_eq(collected.parsed.lines[1], "@@ -1 +1 @@", "collector removes file headers")
  assert_eq(collected.parsed.lines[3], "+working content", "collector retains changed lines")

  local source_bufnr = vim.fn.bufadd(target)
  vim.fn.bufload(source_bufnr)
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "unsaved content" })
  vim.bo[source_bufnr].modified = true
  local modified_state = service._prepare({ path = target })
  assert_eq(modified_state.source_modified, true, "diff detects unsaved source changes")

  local original_stream = runner.stream
  local pending_complete
  local killed = false
  runner.stream = function(_, _, handlers)
    pending_complete = handlers.on_complete
    return {
      kill = function()
        killed = true
      end,
    }
  end
  local opened_process, diff_bufnr = service.open({ path = target, kind = "vsplit", stream = true })
  assert_eq(opened_process ~= nil, true, "public diff API returns its process first")
  vim.api.nvim_buf_delete(diff_bufnr, { force = true })
  assert_eq(killed, true, "wiping a loading diff cancels its process")
  local cancelled_ok = pcall(pending_complete, {
    code = 124,
    signal = 15,
    stderr = { "cancelled" },
  })
  assert_eq(cancelled_ok, true, "cancelled completion is ignored")
  runner.stream = original_stream
  vim.api.nvim_buf_delete(source_bufnr, { force = true })

  vim.fn.writefile({ "/file.lua/0/Initial file//" }, cvs_dir .. "/Entries")
  local missing, missing_err = service._prepare({ path = target })
  assert_eq(missing, nil, "added file has no CVS base")
  assert_eq(missing_err.kind, "base_revision_missing", "missing base reports a specific error")

  config.setup()
  vim.fn.delete(temp_dir, "rf")
end
