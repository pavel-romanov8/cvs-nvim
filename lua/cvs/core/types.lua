local M = {}

M.status = {
  modified = "modified",
  added = "added",
  removed = "removed",
  conflict = "conflict",
  patched = "patched",
  updated = "updated",
  unknown = "unknown",
}

M.events = {
  changed = "CvsChanged",
  status_refreshed = "CvsStatusRefreshed",
}

return M
