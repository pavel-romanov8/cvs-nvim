local service = require("cvs.features.files.service")
local capabilities = require("cvs.cvs.capabilities")
local queue = require("cvs.core.queue")
local runner = require("cvs.cvs.runner")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local original_buf_get_name = vim.api.nvim_buf_get_name
  local original_detect = capabilities.detect
  local original_is_busy = queue.is_busy
  local original_enqueue = queue.enqueue
  local original_run = runner.run

  vim.api.nvim_buf_get_name = function()
    return ""
  end

  local ok, err = pcall(function()
    local resolved, resolve_err = service._resolve_target_path({})
    assert_eq(resolved, nil, "missing add path returns nil")
    assert_eq(resolve_err.kind, "path_missing", "missing add path returns path_missing error")

    local label = service._scope_label({ root_dir = "/tmp/work" }, "/tmp/work/pkg/file.lua")
    assert_eq(label, "pkg/file.lua", "scope label is relative to workspace")

    local files, paths = service._normalize_workspace_files({ root_dir = "/tmp/work" }, {
      "pkg/one.lua",
      "/tmp/work/pkg/two.lua",
      "pkg/one.lua",
    })
    assert_eq(#files, 2, "workspace files are deduplicated")
    assert_eq(files[1], "pkg/one.lua", "relative workspace file is preserved")
    assert_eq(files[2], "pkg/two.lua", "absolute workspace file becomes relative")
    assert_eq(paths[2], "/tmp/work/pkg/two.lua", "absolute target path is retained")

    local outside, _, outside_err = service._normalize_workspace_files({ root_dir = "/tmp/work" }, {
      "../outside.lua",
    })
    assert_eq(outside, nil, "outside workspace path is rejected")
    assert_eq(outside_err.kind, "path_outside_workspace", "outside path returns a typed error")

    require("cvs.config").setup({
      notifications = { enabled = false },
    })
    capabilities.detect = function()
      return { executable = true, bin = "cvs" }
    end
    queue.is_busy = function()
      return false
    end
    queue.enqueue = function(_, work)
      work(function() end)
    end

    local command
    local commands = {}
    local cwd
    runner.run = function(next_command, opts, callback)
      command = next_command
      commands[#commands + 1] = next_command
      cwd = opts.cwd
      callback({ code = 0, stdout = {}, stderr = {} })
    end

    local metadata
    service.add({
      workspace = { root_dir = "/tmp/work" },
      files = { "pkg/one.lua", "pkg/two.lua" },
      on_complete = function(_, value)
        metadata = value
      end,
    })
    assert_eq(table.concat(command, " "), "cvs add pkg/one.lua pkg/two.lua", "bulk add uses only file targets")
    assert_eq(cwd, "/tmp/work", "bulk add runs from workspace root")
    assert_eq(metadata.path, nil, "bulk add has no singular path")
    assert_eq(#metadata.files, 2, "bulk add callback includes files")

    service.add({
      workspace = { root_dir = "/tmp/work" },
      files = { "assets/logo.png" },
      binary = true,
      on_complete = function(_, value)
        metadata = value
      end,
    })
    assert_eq(table.concat(command, " "), "cvs add -kb assets/logo.png", "binary add passes -kb before its target")
    assert_eq(metadata.binary, true, "binary add callback identifies its mode")

    commands = {}
    local discard_result
    service.discard({
      workspace = { root_dir = "/tmp/work" },
      items = {
        { path = "modified.lua", status = "modified" },
        { path = "conflict.lua", status = "conflict" },
        { path = "missing.lua", status = "missing" },
        { path = "added.lua", status = "added" },
        { path = "removed.lua", status = "removed" },
      },
      on_complete = function(result, value)
        discard_result = result
        metadata = value
      end,
    })
    assert_eq(#commands, 5, "discard runs one command per CVS status")
    assert_eq(table.concat(commands[1], " "), "cvs -q update -C modified.lua", "modified files are reverted")
    assert_eq(table.concat(commands[2], " "), "cvs -q update -C conflict.lua", "conflicts are reverted")
    assert_eq(table.concat(commands[3], " "), "cvs -q update missing.lua", "missing files are restored")
    assert_eq(table.concat(commands[4], " "), "cvs remove -f added.lua", "newly added files are removed")
    assert_eq(table.concat(commands[5], " "), "cvs add removed.lua", "scheduled removals are restored")
    assert_eq(discard_result.code, 0, "successful discard reports success")
    assert_eq(metadata.changed_count, 5, "discard reports every changed file")

    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.writefile({ "new" }, temp_dir .. "/unknown.lua")
    service.discard({
      workspace = { root_dir = temp_dir },
      items = {
        { path = "unknown.lua", status = "unknown" },
      },
      on_complete = function(result, value)
        discard_result = result
        metadata = value
      end,
    })
    assert_eq(discard_result.code, 0, "unknown file deletion reports success")
    assert_eq(metadata.changed_count, 1, "unknown file deletion reports its change")
    assert_eq(vim.fn.filereadable(temp_dir .. "/unknown.lua"), 0, "unknown file is deleted")

    vim.fn.writefile({ "recovery" }, temp_dir .. "/.#unknown.lua.1.7")
    service.discard({
      workspace = { root_dir = temp_dir },
      items = {
        { path = ".#unknown.lua.1.7", status = "unknown" },
      },
      on_complete = function(result, value)
        discard_result = result
        metadata = value
      end,
    })
    assert_eq(discard_result.code, 0, "CVS backup deletion reports success")
    assert_eq(metadata.changed_count, 1, "CVS backup deletion reports its change")
    assert_eq(vim.fn.filereadable(temp_dir .. "/.#unknown.lua.1.7"), 0, "CVS backup is deleted")

    vim.fn.writefile({ "modified" }, temp_dir .. "/modified.lua")
    runner.run = function(_, _, callback)
      vim.fn.writefile({ "discarded" }, temp_dir .. "/.#modified.lua.1.7")
      callback({ code = 0, stdout = {}, stderr = {} })
    end
    service.discard({
      workspace = { root_dir = temp_dir },
      items = {
        { path = "modified.lua", status = "modified" },
      },
      on_complete = function(result)
        discard_result = result
      end,
    })
    assert_eq(discard_result.code, 0, "discard backup cleanup reports success")
    assert_eq(vim.fn.filereadable(temp_dir .. "/.#modified.lua.1.7"), 0, "new CVS discard backup is deleted")

    vim.fn.writefile({ "older recovery" }, temp_dir .. "/.#modified.lua.1.6")
    service.discard({
      workspace = { root_dir = temp_dir },
      items = {
        { path = "modified.lua", status = "modified" },
      },
    })
    assert_eq(vim.fn.filereadable(temp_dir .. "/.#modified.lua.1.6"), 1, "pre-existing CVS backup is preserved")
    vim.fn.delete(temp_dir, "rf")
  end)

  vim.api.nvim_buf_get_name = original_buf_get_name
  capabilities.detect = original_detect
  queue.is_busy = original_is_busy
  queue.enqueue = original_enqueue
  runner.run = original_run

  if not ok then
    error(err)
  end
end
