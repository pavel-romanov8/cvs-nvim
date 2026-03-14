local entries = require("cvs.cvs.entries")
local errors = require("cvs.core.errors")
local util = require("cvs.core.util")

local M = {}

local function has_metadata(dir)
  local cvs_dir = util.path_join(dir, "CVS")
  return vim.fn.isdirectory(cvs_dir) == 1 and vim.fn.filereadable(util.path_join(cvs_dir, "Root")) == 1
end

local function parent_dir(path)
  local parent = vim.fs.dirname(path)
  if parent == nil or parent == path then
    return nil
  end

  return parent
end

local function find_workspace_root(start_dir)
  local candidate = nil
  local dir = start_dir

  while dir do
    if has_metadata(dir) then
      candidate = dir
    end

    dir = parent_dir(dir)
  end

  return candidate
end

function M.detect(path)
  local resolved = util.resolve_path(path)
  if not resolved then
    return nil, errors.new("path_missing", "could not resolve a file or directory")
  end

  local start_dir = vim.fn.isdirectory(resolved) == 1 and resolved or vim.fs.dirname(resolved)
  if not start_dir then
    return nil, errors.new("path_missing", ("could not determine a parent directory for %s"):format(resolved))
  end

  local root_dir = find_workspace_root(start_dir)
  if not root_dir then
    return nil, errors.new("workspace_not_found", ("no CVS metadata found for %s"):format(resolved), {
      path = resolved,
    })
  end

  local cvs_dir = util.path_join(root_dir, "CVS")

  return {
    path = resolved,
    start_dir = start_dir,
    root_dir = root_dir,
    cvs_dir = cvs_dir,
    cvs_root = util.read_first_line(util.path_join(cvs_dir, "Root")),
    repository = util.read_first_line(util.path_join(cvs_dir, "Repository")),
    sticky_tag = util.read_first_line(util.path_join(cvs_dir, "Tag")),
    entries = entries.load(util.path_join(cvs_dir, "Entries")),
  }
end

return M
