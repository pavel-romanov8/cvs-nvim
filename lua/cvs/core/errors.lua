local M = {}

function M.new(kind, message, context)
  return {
    kind = kind,
    message = message,
    context = context or {},
  }
end

function M.is(err, kind)
  return type(err) == "table" and err.kind == kind
end

function M.to_string(err)
  if type(err) == "string" then
    return err
  end

  if type(err) ~= "table" then
    return "unknown cvs.nvim error"
  end

  if err.kind and err.message then
    return ("%s: %s"):format(err.kind, err.message)
  end

  return vim.inspect(err)
end

return M
