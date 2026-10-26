-- Loads src/ modules the way scripts/build.py bundles them, with small stand-ins
-- for the ttt modules they require, and runs every tests/*_test.lua.
local stubs = {}

local function utf8_len(s)
  local _, n = tostring(s):gsub("[^\128-\191]", "")
  return n
end

stubs["ttt.text"] = {
  width = utf8_len,
  truncate = function(s)
    return s
  end,
  wrap = function(s)
    return { s }
  end,
}

local store = {}
stubs["ttt.storage"] = {
  get = function(k)
    return store[k]
  end,
  set = function(k, v)
    store[k] = v
  end,
}

stubs["ttt.system"] = {}

local loaded = {}

local function module_path(name)
  local rel = name:gsub("%.", "/")
  for _, candidate in ipairs({ rel .. ".lua", rel .. "/init.lua" }) do
    local path = ROOT .. "/src/" .. candidate
    if readfile(path) then
      return path
    end
  end
end

function require(name)
  if loaded[name] ~= nil then
    return loaded[name]
  end
  if stubs[name] then
    loaded[name] = stubs[name]
    return stubs[name]
  end
  local path = module_path(name)
  if not path then
    error("no module " .. name .. " in src/ and no stub for it in tests/harness.lua", 2)
  end
  local chunk = assert(loadstring(readfile(path), "@" .. path))
  local value = chunk()
  if value == nil then
    value = true
  end
  loaded[name] = value
  return value
end

local current = { passed = 0, failed = 0 }

local function show(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function eq(actual, expected, what)
  if actual ~= expected then
    error((what and (what .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function ok(cond, what)
  if not cond then
    error(what or "expected true", 2)
  end
end

function test(name, fn)
  local good, err = pcall(fn)
  if good then
    current.passed = current.passed + 1
  else
    current.failed = current.failed + 1
    print("FAIL " .. current.file .. ": " .. name .. "\n     " .. tostring(err))
  end
end

for _, spec in ipairs(SPECS) do
  current.file = spec:match("([^/]+)$")
  local chunk = assert(loadstring(readfile(spec), "@" .. spec))
  chunk()
end

print(string.format("%d passed, %d failed", current.passed, current.failed))
FAILED = current.failed > 0
