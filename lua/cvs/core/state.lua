local M = {
  workspaces = {},
  status_cache = {},
  buffers = {},
}

local uv = vim.uv or vim.loop

local function workspace_key(root_dir)
  return uv.fs_realpath(root_dir) or root_dir
end

function M.set_snapshot(root_dir, snapshot)
  M.workspaces[workspace_key(root_dir)] = snapshot
end

function M.get_snapshot(root_dir)
  return M.workspaces[workspace_key(root_dir)]
end

function M.set_status_cache(root_dir, key, entry)
  root_dir = workspace_key(root_dir)
  M.status_cache[root_dir] = M.status_cache[root_dir] or {}
  M.status_cache[root_dir][key] = entry
end

function M.get_status_cache(root_dir, key)
  local workspace = M.status_cache[workspace_key(root_dir)]
  return workspace and workspace[key] or nil
end

function M.invalidate_status_cache(root_dir)
  root_dir = workspace_key(root_dir)
  M.status_cache[root_dir] = nil
  M.workspaces[root_dir] = nil
end

function M.attach_buffer(bufnr, data)
  M.buffers[bufnr] = data
end

function M.get_buffer(bufnr)
  return M.buffers[bufnr]
end

function M.find_buffer(predicate)
  for bufnr, data in pairs(M.buffers) do
    if predicate(bufnr, data) then
      return bufnr, data
    end
  end

  return nil, nil
end

function M.detach_buffer(bufnr)
  M.buffers[bufnr] = nil
end

return M
