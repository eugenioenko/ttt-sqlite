local R = require("core.results")

-- What sqlite3 3.54 -json prints for three statements, one of them without
-- rows (it prints nothing for that one), and a dot-command's text line.
local SAMPLE = [==[
[{"id":2,"name":"b","id":"dup"},
{"id":9223372036854775807,"name":null,"id":""},
{"id":-1.5e+300,"name":"NULL","id":"line\nbreak \"q\" é 😀 ], },"}]
note from a dot-command
[{"n":1}]
]==]

local function parse(text, limit)
  local p = R.stream(limit)
  R.feed(p, text)
  return R.finish(p, true)
end

local function dump(sets, notes)
  local out = {}
  for _, set in ipairs(sets) do
    out[#out + 1] = table.concat(set.columns, ",")
      .. " truncated="
      .. tostring(set.truncated)
      .. " dropped="
      .. set.dropped
    for c in ipairs(set.columns) do
      out[#out + 1] = "numeric " .. c .. " " .. tostring(set.numeric[c])
    end
    for _, row in ipairs(set.rows) do
      local cells = {}
      for c in ipairs(set.columns) do
        cells[c] = row[c] == R.NULL and "<NULL>" or ("[" .. row[c] .. "]")
      end
      out[#out + 1] = table.concat(cells, " ")
    end
  end
  for _, n in ipairs(notes) do
    out[#out + 1] = "note " .. n
  end
  return table.concat(out, "\n")
end

test("keeps column order and duplicate column names", function()
  local sets = parse(SAMPLE)
  eq(#sets, 2)
  eq(table.concat(sets[1].columns, ","), "id,name,id")
  eq(sets[1].rows[1][3], "dup")
end)

test("keeps integers beyond 2^53 exact, as text", function()
  local sets = parse(SAMPLE)
  eq(sets[1].rows[2][1], "9223372036854775807")
  eq(sets[1].rows[3][1], "-1.5e+300")
  eq(sets[1].numeric[1], true)
end)

test("tells NULL from an empty string and the text NULL", function()
  local sets = parse(SAMPLE)
  eq(sets[1].rows[2][2], R.NULL)
  eq(sets[1].rows[2][3], "")
  eq(sets[1].rows[3][2], "NULL")
  eq(sets[1].numeric[2], false, "a column with text is not numeric")
  eq(R.text(sets[1].rows[2][2]), "NULL")
end)

test("decodes escapes, \\u and surrogate pairs", function()
  local sets = parse(SAMPLE)
  eq(sets[1].rows[3][3], 'line\nbreak "q" é 😀 ], },')
end)

test("keeps lines outside the JSON as notes", function()
  local _, notes = parse(SAMPLE)
  eq(#notes, 1)
  eq(notes[1], "note from a dot-command")
end)

test("gives the same result for every way of splitting the output", function()
  local expected = dump(parse(SAMPLE))
  for cut = 1, #SAMPLE - 1 do
    local p = R.stream()
    R.feed(p, SAMPLE:sub(1, cut))
    R.feed(p, SAMPLE:sub(cut + 1))
    eq(dump(R.finish(p, true)), expected, "split at byte " .. cut)
  end
end)

test("carries a line longer than a chunk over to the next chunks", function()
  local long = string.rep("x", 200000)
  local text = '[{"v":"' .. long .. '"},\n{"v":"end"}]\n'
  local p = R.stream()
  for i = 1, #text, 65536 do
    R.feed(p, text:sub(i, i + 65535))
  end
  local sets = assert(R.finish(p, true))
  eq(#sets[1].rows, 2)
  eq(#sets[1].rows[1][1], 200000)
  eq(sets[1].rows[2][1], "end")
end)

test("keeps limit rows per set and counts the rest", function()
  local sets = parse(SAMPLE, 1)
  eq(#sets[1].rows, 1)
  eq(sets[1].truncated, true)
  eq(sets[1].dropped, 2)
  eq(#sets[2].rows, 1, "the next set starts its own count")
  eq(sets[2].truncated, false)
end)

test("counts dropped rows the same way when they arrive in pieces", function()
  local p = R.stream(1)
  for line in SAMPLE:gmatch("[^\n]*\n") do
    R.feed(p, line)
  end
  local sets = assert(R.finish(p, true))
  eq(sets[1].dropped, 2)
  eq(sets[2].rows[1][1], "1")
end)

test("drops a row cut short when sqlite3 was stopped", function()
  local p = R.stream()
  R.feed(p, '[{"a":1},\n{"a":2},\n{"a":3')
  local sets = assert(R.finish(p, false))
  eq(#sets[1].rows, 2)
end)

test("reports output that is not JSON", function()
  local sets, err = parse('[{"a":1},\n{"a" 2}]\n')
  eq(sets, nil)
  ok(err:find("expected ':'", 1, true), err)
  local _, cut = parse('[{"a":1},\n{"a":2')
  ok(cut:find("unexpected end", 1, true), cut)
end)

test("groups records by their tag column", function()
  local sets = parse('[{"k":"obj","name":"t"},\n{"k":"obj","name":"u"}]\n[{"k":"size","bytes":4096}]\n')
  local t = R.tagged(sets)
  eq(#t.obj, 2)
  eq(t.obj[2].name, "u")
  eq(t.size[1].bytes, "4096")
end)
