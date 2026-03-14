local M = {}

local queues = {}

local function ensure(key)
  if not queues[key] then
    queues[key] = {
      busy = false,
      pending = {},
    }
  end

  return queues[key]
end

local function step(key)
  local queue = ensure(key)

  if queue.busy then
    return
  end

  local item = table.remove(queue.pending, 1)
  if not item then
    return
  end

  queue.busy = true

  local function done()
    queue.busy = false
    vim.schedule(function()
      step(key)
    end)
  end

  local ok, err = pcall(item.fn, done)
  if ok then
    return
  end

  queue.busy = false

  if item.on_error then
    item.on_error(err)
  else
    vim.schedule(function()
      error(err)
    end)
  end

  vim.schedule(function()
    step(key)
  end)
end

function M.enqueue(key, fn, on_error)
  local queue = ensure(key)

  queue.pending[#queue.pending + 1] = {
    fn = fn,
    on_error = on_error,
  }

  step(key)
end

function M.is_busy(key)
  return ensure(key).busy
end

return M
