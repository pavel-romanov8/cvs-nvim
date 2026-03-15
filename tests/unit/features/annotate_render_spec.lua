local render = require("cvs.features.annotate.render")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

return function()
  local lines = render.lines({
    { author = "mary", date = "27-Mar-96" },
    { author = "verylongauthor", date = "28-Mar-96 14:32" },
  }, {
    line_count = 3,
    author_width = 8,
  })

  assert_eq(lines[1], "mary     | 27-Mar-96", "padded author line")
  assert_eq(lines[2], "verylon~ | 28-Mar-96 14:32", "truncated author line")
  assert_eq(lines[3], "", "blank padded line")
end
