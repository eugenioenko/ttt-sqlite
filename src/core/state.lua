local storage = require("ttt.storage")

local S = {}

S.DEFAULTS = {
  sqlite3_path = "sqlite3",
  page_size = 50,
  count_limit_mib = 64,
  query_row_limit = 5000,
  query_timeout_s = 300,
}

S.CATALOG_TIMEOUT_MS = 30000
S.VERSION_TIMEOUT_MS = 10000
S.OUTPUT_LIMIT = 64 * 1024 * 1024

S.settings = storage.get("settings") or {}
for k, v in pairs(S.DEFAULTS) do
  if S.settings[k] == nil or S.settings[k] == "" then
    S.settings[k] = v
  end
end

S.recent = storage.get("recent") or {}
S.dbs = {}
S.current = nil
S.panels = {}

function S.save_settings()
  storage.set("settings", S.settings)
end

function S.page_size()
  return tonumber(S.settings.page_size) or S.DEFAULTS.page_size
end

function S.query_timeout_ms()
  local s = tonumber(S.settings.query_timeout_s) or S.DEFAULTS.query_timeout_s
  return math.max(s, 0) * 1000
end

function S.binary()
  local path = S.settings.sqlite3_path
  if type(path) ~= "string" or path == "" then
    return S.DEFAULTS.sqlite3_path
  end
  return path
end

function S.remember(path)
  local list = { path }
  for _, p in ipairs(S.recent) do
    if p ~= path and #list < 10 then
      list[#list + 1] = p
    end
  end
  S.recent = list
  storage.set("recent", list)
end

function S.forget(path)
  local list = {}
  for _, p in ipairs(S.recent) do
    if p ~= path then
      list[#list + 1] = p
    end
  end
  S.recent = list
  storage.set("recent", list)
end

function S.attachments(path)
  return storage.get("attach:" .. path) or {}
end

function S.save_attachments(path, list)
  storage.set("attach:" .. path, #list > 0 and list or nil)
end

-- Any live panel's redraw repaints the whole screen.
function S.redraw()
  for _, p in pairs(S.panels) do
    if pcall(p.redraw, p) then
      return
    end
  end
end

return S
