local text = require("ttt.text")

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

function U.width(s)
  return text.width(tostring(s))
end

function U.clip(s, n)
  return text.truncate(tostring(s), n, "…")
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

function U.wrap(s, width)
  local indent = s:match("^%s*")
  local inner = math.max(width - text.width(indent), 1)
  local rest = s:sub(#indent + 1)
  local first = text.wrap(rest, inner)[1] or ""
  local out = { indent .. first }
  local tail = rest:sub(#first + 1):gsub("^ +", "")
  if tail ~= "" then
    for _, line in ipairs(text.wrap(tail, math.max(inner - 2, 1))) do
      out[#out + 1] = indent .. "  " .. line
    end
  end
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

function U.duration(ms)
  local s = math.floor((ms or 0) / 1000)
  if s < 60 then
    return U.plural(s, "second")
  elseif s < 3600 then
    return U.plural(math.floor(s / 60), "minute")
  end
  return U.plural(math.floor(s / 3600), "hour")
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
