local U = {}

function U.trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

function U.basename(path)
  local name = tostring(path or ""):match("([^/]+)/*$")
  return name or tostring(path or "")
end

function U.stem(path)
  local name = U.basename(path)
  return (name:gsub("%.[^%.]+$", ""))
end

local function wide(cp)
  return (cp >= 0x1100 and cp <= 0x115F)
    or (cp >= 0x2E80 and cp <= 0xA4CF)
    or (cp >= 0xAC00 and cp <= 0xD7A3)
    or (cp >= 0xF900 and cp <= 0xFAFF)
    or (cp >= 0xFE30 and cp <= 0xFE4F)
    or (cp >= 0xFF00 and cp <= 0xFF60)
    or (cp >= 0xFFE0 and cp <= 0xFFE6)
    or cp >= 0x1F300
end

-- Approximate terminal columns, for sizing table columns only: ttt measures
-- and clips what it draws, so an estimate that is off just wastes a cell.
function U.width(s)
  s = tostring(s)
  if not s:find("[\128-\255]") then
    return #s
  end
  local n, i = 0, 1
  while i <= #s do
    local c = s:byte(i)
    if c < 0x80 then
      n = n + 1
      i = i + 1
    elseif c >= 0xF0 then
      n = n + 2
      i = i + 4
    elseif c >= 0xE0 then
      local cp = (c - 0xE0) * 0x1000 + ((s:byte(i + 1) or 0x80) - 0x80) * 0x40 + ((s:byte(i + 2) or 0x80) - 0x80)
      n = n + (wide(cp) and 2 or 1)
      i = i + 3
    elseif c >= 0xC0 then
      n = n + 1
      i = i + 2
    else
      i = i + 1
    end
  end
  return n
end

function U.clip(s, n)
  s = tostring(s)
  if U.width(s) <= n then
    return s
  end
  local out, count, i = {}, 0, 1
  while i <= #s and count < n - 1 do
    local c = s:byte(i)
    local len = c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1
    out[#out + 1] = s:sub(i, i + len - 1)
    count = count + 1
    i = i + len
  end
  return table.concat(out) .. "…"
end

function U.one_line(s)
  s = tostring(s)
  s = s:gsub("\r\n", "↵"):gsub("[\r\n]", "↵"):gsub("\t", " ")
  return s
end

function U.lines(s)
  local out, start = {}, 1
  s = tostring(s or "")
  while true do
    local i = s:find("\n", start, true)
    if not i then
      out[#out + 1] = s:sub(start)
      break
    end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
  return out
end

-- Splits s at spaces into lines of at most width runes; a word longer than
-- width is cut.
local function take(s, n)
  local i, count = 1, 0
  while i <= #s and count < n do
    local c = s:byte(i)
    i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
    count = count + 1
  end
  return s:sub(1, i - 1), s:sub(i)
end

local function words(s)
  local out, start = {}, 1
  while true do
    local i = s:find(" ", start, true)
    if not i then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
end

-- Splits s at spaces into lines of at most width runes; a word longer than
-- width is cut. string.gmatch is avoided: it crashes inside ttt callbacks.
function U.wrap(s, width)
  local out, line = {}, ""
  local indent = s:match("^%s*")
  for _, word in ipairs(words(s:sub(#indent + 1))) do
    local candidate = line == "" and (indent .. word) or (line .. " " .. word)
    if U.width(candidate) <= width or line == "" then
      line = candidate
    else
      out[#out + 1] = line
      line = indent .. "  " .. word
    end
    while U.width(line) > width do
      local head, rest = take(line, width)
      out[#out + 1] = head
      line = rest
    end
  end
  out[#out + 1] = line
  return out
end

-- A one-line CREATE TABLE as one column or constraint per line. SQL that
-- already has line breaks is left as written.
function U.format_create(sql)
  sql = tostring(sql or "")
  if sql:find("\n", 1, true) or not sql:upper():find("^%s*CREATE%s+[%w%s]-TABLE") then
    return U.lines(sql)
  end
  local open = sql:find("(", 1, true)
  if not open then
    return { sql }
  end
  local lines, depth, quote, start = { sql:sub(1, open) }, 0, nil, open + 1
  for i = open + 1, #sql do
    local c = sql:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      end
    elseif c == "'" or c == '"' or c == "`" then
      quote = c
    elseif c == "[" then
      quote = "]"
    elseif c == "(" then
      depth = depth + 1
    elseif c == ")" then
      if depth == 0 then
        lines[#lines + 1] = "  " .. U.trim(sql:sub(start, i - 1))
        lines[#lines + 1] = U.trim(sql:sub(i))
        return lines
      end
      depth = depth - 1
    elseif c == "," and depth == 0 then
      lines[#lines + 1] = "  " .. U.trim(sql:sub(start, i - 1)) .. ","
      start = i + 1
    end
  end
  return { sql }
end

function U.ident(name)
  return '"' .. tostring(name):gsub('"', '""') .. '"'
end

function U.literal(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

function U.qualified(schema, name)
  return U.ident(schema) .. "." .. U.ident(name)
end

local function percent(c)
  return string.format("%%%02X", string.byte(c))
end

-- A file: URI keeps sqlite3 from reading a non-database path as an SQL script
-- (it does that for existing *.sql and *.txt files) and from creating files.
function U.uri(path, write)
  local encoded = tostring(path):gsub("[^%w%-%._~/]", percent)
  return "file:" .. encoded .. "?mode=" .. (write and "rw" or "ro")
end

function U.count(n)
  n = tonumber(n)
  if not n then
    return ""
  end
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

function U.bytes(n)
  n = tonumber(n) or 0
  if n < 1024 then
    return n .. " B"
  elseif n < 1024 * 1024 then
    return string.format("%.1f KiB", n / 1024)
  elseif n < 1024 * 1024 * 1024 then
    return string.format("%.1f MiB", n / 1024 / 1024)
  end
  return string.format("%.2f GiB", n / 1024 / 1024 / 1024)
end

function U.plural(n, one, many)
  return U.count(n) .. " " .. (n == 1 and one or (many or one .. "s"))
end

function U.ms(seconds)
  local ms = math.floor((seconds or 0) * 1000 + 0.5)
  if ms < 1000 then
    return ms .. " ms"
  end
  return string.format("%.2f s", ms / 1000)
end

-- Bound arguments come first, then the caller's.
function U.bind(fn, ...)
  local bound = { n = select("#", ...), ... }
  return function(...)
    local n = select("#", ...)
    local args = { unpack(bound, 1, bound.n) }
    for i = 1, n do
      args[bound.n + i] = select(i, ...)
    end
    return fn(unpack(args, 1, bound.n + n))
  end
end

return U
