local U = require("core.util")
local Sqlite = require("core.sqlite")

test("quotes identifiers and literals", function()
  eq(U.ident('we"ird'), '"we""ird"')
  eq(U.literal("it's"), "'it''s'")
  eq(U.qualified("my db", "a.b"), '"my db"."a.b"')
end)

test("opens files by URI, read-only unless asked to write", function()
  eq(U.uri("/data/app.db"), "file:/data/app.db?mode=ro")
  eq(U.uri("/data/app.db", true), "file:/data/app.db?mode=rw")
  eq(U.uri("/tmp/we ird?#%.db"), "file:/tmp/we%20ird%3F%23%25.db?mode=ro")
end)

test("attaches every schema with a quoted URI and alias, then turns on bail", function()
  local db = { path = "/d/main.db", attachments = { { path = "/d/o'ther.db", alias = 'x"y' } } }
  local args = Sqlite.build_args(db, {})
  local text = table.concat(args, " | ")
  eq(
    text,
    '-noinit | -batch | -json | -cmd | ATTACH \'file:/d/o%27ther.db?mode=ro\' AS "x""y" | -cmd | .bail on | file:/d/main.db?mode=ro'
  )
  local rw = Sqlite.build_args(db, { write = true, bail = false })
  eq(rw[5], 'ATTACH \'file:/d/o%27ther.db?mode=rw\' AS "x""y"')
  eq(rw[#rw], "file:/d/main.db?mode=rw")
  eq(#rw, 6, "no .bail on")
end)

test("recognizes the error of a read-only run that reached a write", function()
  ok(Sqlite.refused_write("Runtime error near line 2: attempt to write a readonly database (8)"))
  ok(not Sqlite.refused_write("Parse error near line 1: no such table: t"))
  ok(not Sqlite.refused_write(nil))
end)

test("binds arguments before the caller's", function()
  local function join(...)
    return table.concat({ ... }, ",")
  end
  eq(U.bind(join, "a", "b")("c", "d"), "a,b,c,d")
  eq(U.bind(join)("x"), "x")
end)

test("formats durations and counts", function()
  eq(U.duration(10000), "10 seconds")
  eq(U.duration(300000), "5 minutes")
  eq(U.duration(3600000), "1 hour")
  eq(U.count(1234567), "1,234,567")
end)
