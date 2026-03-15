local M = {
  workspaces = {},
  buffers = {},
}

function M.set_snapshot(root_dir, snapshot)
  M.workspaces[root_dir] = snapshot
end

function M.get_snapshot(root_dir)
  return M.workspaces[root_dir]
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
