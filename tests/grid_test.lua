local ttt = require("ttt")
local Grid = require("components.grid")
local R = require("core.results")

test("aligns values and preserves column order, including duplicate names", function()
  local lines = Grid.row_lines({ "id", "name", "id" }, { "42", "Alice", "duplicate" })
  eq(table.concat(lines, "\n"), "id    42\nname  Alice\nid    duplicate")
end)

test("preserves multiline values, blank lines, whitespace and trailing newlines", function()
  local lines = Grid.row_lines({ "notes", "id" }, { "first\r\n\n  second\tpart\n", "42" })
  eq(table.concat(lines, "\n"), "notes  first\n       \n         second\tpart\n       \nid     42")
end)

test("keeps nulls, empty strings, long values and numeric precision", function()
  local long = string.rep("x", 1000)
  local lines = Grid.row_lines({ "null", "empty", "integer", "real", "long", "missing" }, {
    R.NULL,
    "",
    "9223372036854775807",
    "864.7859999999999",
    long,
  })
  eq(
    table.concat(lines, "\n"),
    table.concat({
      "null     NULL",
      'empty    ""',
      "integer  9223372036854775807",
      "real     864.7859999999999",
      "long     " .. long,
      "missing  NULL",
    }, "\n")
  )
end)

test("View and Enter open readonly row snapshots with page-relative titles", function()
  local spec
  local panel = {
    table = function(_, opts)
      spec = opts
    end,
  }
  local grid = Grid.new_grid()
  Grid.grid(panel, grid, {
    columns = { "id" },
    rows = { { "42" }, { "43" } },
    offset = 50,
    row_title = "users",
  })
  local opened = {}
  local original = ttt.open_readonly
  ttt.open_readonly = function(title, lines)
    opened[#opened + 1] = { title = title, lines = lines }
  end
  local good, err = pcall(function()
    spec.on_command("view", 1)
    spec.on_activate(2)
    spec.on_activate(3)
  end)
  ttt.open_readonly = original
  ok(good, err)
  eq(#opened, 2)
  eq(opened[1].title, "users · Row 51")
  eq(opened[2].title, "users · Row 52")
  eq(table.concat(opened[1].lines, "\n"), "id  42")
  eq(table.concat(opened[2].lines, "\n"), "id  43")
end)
