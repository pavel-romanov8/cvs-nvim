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
    local cwd
    runner.run = function(next_command, opts, callback)
      command = next_command
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
