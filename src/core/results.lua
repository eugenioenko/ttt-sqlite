-- Parses what `sqlite3 -json` prints: one JSON array of flat objects per
-- statement that returned rows, one after another. ttt.json would lose the
-- column order and duplicate column names, and turn large integers into
-- floats, so this reads the objects itself and keeps every value as text.
local M = {}

local function null_text()
  return "NULL"
end

M.NULL = setmetatable({}, { __tostring = null_text })

local function utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

local ESCAPES = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- Raised when the text ends inside an item: the item is parsed again once
-- more output has arrived.
local MORE = {}

local function fail(i, what)
  error({ parse = true, message = "unexpected sqlite3 output at byte " .. i .. ": " .. what }, 0)
end

local function short(p, i, what)
  if p.final then
    fail(p.base + i, what or "unexpected end")
  end
  error(MORE, 0)
end

local function byte_at(p, i)
  local b = p.s:byte(i)
  if not b then
    short(p, i)
  end
  return b
end

local function skip(p, i)
  local _, e = p.s:find("^[ \t\r\n,]*", i)
  return e + 1
end

local function read_string(p, i)
  local s = p.s
  local parts = {}
  local start = i + 1
  while true do
    local j = s:find('["\\]', start)
    if not j then
      short(p, i, "unterminated string")
    end
    parts[#parts + 1] = s:sub(start, j - 1)
    if s:byte(j) == 34 then
      return table.concat(parts), j + 1
    end
    local c = s:sub(j + 1, j + 1)
    if c == "" then
      short(p, j)
    elseif c == "u" then
      if j + 5 > #s then
        short(p, j)
      end
      local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
      local nexti = j + 6
      if cp >= 0xD800 and cp <= 0xDBFF then
        if nexti + 5 > #s then
          short(p, j)
        end
        local lo = s:sub(nexti, nexti + 1) == "\\u" and tonumber(s:sub(nexti + 2, nexti + 5), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          nexti = nexti + 6
        end
      end
      parts[#parts + 1] = utf8(cp)
      start = nexti
    else
      parts[#parts + 1] = ESCAPES[c] or c
      start = j + 2
    end
  end
end

-- Returns the value as text (or NULL), whether it was a number, and the next
-- position.
local function read_value(p, i)
  local s = p.s
  local b = byte_at(p, i)
  if b == 34 then
    local v, nexti = read_string(p, i)
    return v, false, nexti
  end
  if b == 110 then
    if i + 3 > #s then
      short(p, i)
    end
    if s:sub(i, i + 3) == "null" then
      return M.NULL, false, i + 4
    end
  end
  local _, e = s:find("^[%w%.%+%-]+", i)
  if not e then
    fail(p.base + i, "expected a value")
  end
  if e == #s then
    short(p, i)
  end
  return s:sub(i, e), true, e + 1
end

local function read_object(p, i, set)
  local row, col = {}, 0
  i = skip(p, i + 1)
  while byte_at(p, i) ~= 125 do
    if p.s:byte(i) ~= 34 then
      fail(p.base + i, "expected a column name")
    end
    local name, nexti = read_string(p, i)
    i = skip(p, nexti)
    if byte_at(p, i) ~= 58 then
      fail(p.base + i, "expected ':'")
    end
    i = skip(p, i + 1)
    local value, numeric
    value, numeric, i = read_value(p, i)
    col = col + 1
    if not set.columns[col] then
      set.columns[col] = name
      set.numeric[col] = true
    end
    if value ~= M.NULL and not numeric then
      set.numeric[col] = false
    end
    row[col] = value
    i = skip(p, i)
  end
  return row, i + 1
end

-- sqlite3 -json prints one row per line, and escapes the control characters
-- in strings, so a line ending in "}," or "}]" is exactly one row. Rows past
-- the limit are only counted, which this does without reading their values.
-- Returns the position after the rows it skipped.
local function skip_rows(p, i, set)
  local s = p.s
  while p.set do
    local nl = s:find("\n", i, true)
    if not nl then
      break
    end
    local k = nl - 1
    local b = s:byte(k)
    while b == 32 or b == 13 do
      k = k - 1
      b = s:byte(k)
    end
    if (b ~= 44 and b ~= 93) or s:byte(k - 1) ~= 125 or s:byte(i) ~= 123 then
      break
    end
    set.dropped = set.dropped + 1
    if b == 93 then
      p.set = nil
    end
    i = nl + 1
  end
  return i
end

local function new_set()
  return { columns = {}, numeric = {}, rows = {}, truncated = false, dropped = 0 }
end

-- Parses one item at p.i (a set's "[", a row, a set's "]", or a line of text
-- outside the sets) and returns false at the end of the text.
local function step(p)
  local s, i = p.s, p.i
  local set = p.set
  if not set then
    local _, e = s:find("^%s*", i)
    i = e + 1
    if i > #s then
      p.i = i
      return false
    end
    if s:byte(i) == 91 then
      set = new_set()
      p.set = set
      p.sets[#p.sets + 1] = set
      p.i = i + 1
      return true
    end
    local j = s:find("\n", i, true)
    if not j then
      if not p.final then
        short(p, i)
      end
      j = #s + 1
    end
    p.notes[#p.notes + 1] = s:sub(i, j - 1)
    p.i = j + 1
    return true
  end
  i = skip(p, i)
  local b = byte_at(p, i)
  if b == 93 then
    p.set = nil
    p.i = i + 1
    return true
  end
  if b ~= 123 then
    fail(p.base + i, "expected '{' or ']'")
  end
  if #set.rows >= p.limit then
    set.truncated = true
    local nexti = skip_rows(p, i, set)
    if nexti > i then
      p.i = nexti
      return true
    end
  end
  local row
  row, i = read_object(p, i, set)
  if #set.rows < p.limit then
    set.rows[#set.rows + 1] = row
  else
    set.dropped = set.dropped + 1
  end
  p.i = i
  return true
end

local function run(p)
  while not p.err do
    local i = p.i
    local ok, res = pcall(step, p)
    if not ok then
      p.i = i
      if res ~= MORE then
        p.err = type(res) == "table" and res.message or tostring(res)
      end
      return
    end
    if not res then
      return
    end
  end
end

-- A parser for sqlite3 -json output that arrives in pieces: feed it each
-- chunk, then finish. Rows past limit in a set are counted in dropped and set
-- truncated.
function M.stream(limit)
  return { s = "", i = 1, base = 0, pending = {}, sets = {}, notes = {}, limit = limit or math.huge, final = false }
end

function M.feed(p, chunk)
  if p.err then
    return
  end
  if not chunk:find("\n", 1, true) then
    p.pending[#p.pending + 1] = chunk
    return
  end
  p.pending[#p.pending + 1] = chunk
  p.base = p.base + p.i - 1
  p.s = p.s:sub(p.i) .. table.concat(p.pending)
  p.pending = {}
  p.i = 1
  run(p)
end

-- complete is false when the output was cut short (cancelled, timed out,
-- capped): what is left is an incomplete row and is dropped. Returns sets
-- and notes (lines that were not JSON, from dot-commands), or nil and an
-- error. Each set is { columns, numeric, rows, truncated, dropped }; a row is
-- an array of strings and NULL.
function M.finish(p, complete)
  if complete and not p.err then
    p.base = p.base + p.i - 1
    p.s = p.s:sub(p.i) .. table.concat(p.pending)
    p.pending = {}
    p.i = 1
    p.final = true
    run(p)
    if not p.err and p.set then
      p.err = "unexpected end of sqlite3 output"
    end
  end
  if p.err then
    return nil, p.err
  end
  return p.sets, p.notes
end

-- Rows as tables keyed by column name, for queries the plugin writes itself.
function M.records(set)
  local out = {}
  for r, row in ipairs(set and set.rows or {}) do
    local rec = {}
    for c, name in ipairs(set.columns) do
      local v = row[c]
      if v ~= M.NULL then
        rec[name] = v
      end
    end
    out[r] = rec
  end
  return out
end

-- The records of every set, grouped by their first column, which the
-- plugin's own queries use as a tag: sqlite3 prints nothing for a statement
-- without rows, so position alone cannot say which set is which.
function M.tagged(sets)
  local out = {}
  for _, set in ipairs(sets or {}) do
    for _, rec in ipairs(M.records(set)) do
      local tag = rec[set.columns[1]]
      if tag then
        out[tag] = out[tag] or {}
        table.insert(out[tag], rec)
      end
    end
  end
  return out
end

function M.text(v)
  if v == nil or v == M.NULL then
    return "NULL"
  end
  return v
end

return M
