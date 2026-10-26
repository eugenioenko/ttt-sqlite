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

local function fail(i, what)
  error({ parse = true, message = "unexpected sqlite3 output at byte " .. i .. ": " .. what }, 0)
end

local function skip(s, i)
  local _, e = s:find("^[ \t\r\n,]*", i)
  return e + 1
end

local function read_string(s, i)
  local parts = {}
  local start = i + 1
  while true do
    local j = s:find('["\\]', start)
    if not j then
      fail(i, "unterminated string")
    end
    parts[#parts + 1] = s:sub(start, j - 1)
    if s:byte(j) == 34 then
      return table.concat(parts), j + 1
    end
    local c = s:sub(j + 1, j + 1)
    if c == "u" then
      local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
      local nexti = j + 6
      if cp >= 0xD800 and cp <= 0xDBFF and s:sub(nexti, nexti + 1) == "\\u" then
        local lo = tonumber(s:sub(nexti + 2, nexti + 5), 16)
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
local function read_value(s, i)
  local b = s:byte(i)
  if b == 34 then
    local v, nexti = read_string(s, i)
    return v, false, nexti
  end
  if s:sub(i, i + 3) == "null" then
    return M.NULL, false, i + 4
  end
  local _, e = s:find("^[%w%.%+%-]+", i)
  if not e then
    fail(i, "expected a value")
  end
  return s:sub(i, e), true, e + 1
end

local function read_object(s, i, set)
  local row, col = {}, 0
  i = skip(s, i + 1)
  while s:byte(i) ~= 125 do
    if s:byte(i) ~= 34 then
      fail(i, "expected a column name")
    end
    local name, nexti = read_string(s, i)
    i = skip(s, nexti)
    if s:byte(i) ~= 58 then
      fail(i, "expected ':'")
    end
    i = skip(s, i + 1)
    local value, numeric
    value, numeric, i = read_value(s, i)
    col = col + 1
    if not set.columns[col] then
      set.columns[col] = name
      set.numeric[col] = true
    end
    if value ~= M.NULL and not numeric then
      set.numeric[col] = false
    end
    row[col] = value
    i = skip(s, i)
  end
  return row, i + 1
end

local function read_array(s, i, limit)
  local set = { columns = {}, numeric = {}, rows = {}, truncated = false }
  i = skip(s, i + 1)
  while s:byte(i) == 123 do
    local row
    row, i = read_object(s, i, set)
    if #set.rows < limit then
      set.rows[#set.rows + 1] = row
    else
      set.truncated = true
    end
    i = skip(s, i)
  end
  if s:byte(i) ~= 93 then
    fail(i, "expected ']'")
  end
  return set, i + 1
end

local function parse(s, limit)
  local sets, notes = {}, {}
  local i = 1
  local n = #s
  while true do
    local _, e = s:find("^%s*", i)
    i = e + 1
    if i > n then
      break
    end
    if s:byte(i) == 91 then
      local set
      set, i = read_array(s, i, limit)
      sets[#sets + 1] = set
    else
      local j = s:find("\n", i, true) or n + 1
      notes[#notes + 1] = s:sub(i, j - 1)
      i = j + 1
    end
  end
  return sets, notes
end

-- Returns sets, notes (lines that were not JSON, from dot-commands), or nil
-- and an error. Each set is { columns, numeric, rows, truncated }; a row is an
-- array of strings and NULL. Rows past limit are counted out as truncated.
function M.parse(s, limit)
  local ok, sets, notes = pcall(parse, s or "", limit or math.huge)
  if not ok then
    if type(sets) == "table" and sets.parse then
      return nil, sets.message
    end
    return nil, tostring(sets)
  end
  return sets, notes
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
