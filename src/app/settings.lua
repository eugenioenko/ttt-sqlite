local ttt = require("ttt")
local sys = require("ttt.system")
local U = require("core.util")
local S = require("core.state")
local Sqlite = require("core.sqlite")
local UI = require("components")
local Paths = require("app.paths")

local M = {}

M.PAGE_SIZES = {
  { label = "25 rows per page", value = "25" },
  { label = "50 rows per page", value = "50" },
  { label = "100 rows per page", value = "100" },
  { label = "200 rows per page", value = "200" },
}

M.TIMEOUTS = {
  { label = "10 seconds", value = "10" },
  { label = "30 seconds", value = "30" },
  { label = "1 minute", value = "60" },
  { label = "5 minutes", value = "300" },
  { label = "15 minutes", value = "900" },
  { label = "1 hour", value = "3600" },
  { label = "No timeout", value = "0" },
}

local function binary_path(text)
  local path = U.trim(text)
  if path == "" then
    return S.DEFAULTS.sqlite3_path
  end
  if path:find("/", 1, true) or path:sub(1, 1) == "~" then
    return Paths.normalize(path)
  end
  return path
end

local function store(v, path, version)
  S.settings.sqlite3_path = path
  S.settings.page_size = tonumber(v.page_size) or S.DEFAULTS.page_size
  S.settings.count_limit_mib = tonumber(v.count_limit_mib) or S.DEFAULTS.count_limit_mib
  S.settings.query_row_limit = tonumber(v.query_row_limit) or S.DEFAULTS.query_row_limit
  S.settings.query_timeout_s = tonumber(v.query_timeout_s) or S.DEFAULTS.query_timeout_s
  S.save_settings()
  ttt.notify("Using sqlite3 " .. version .. (path == S.DEFAULTS.sqlite3_path and "" or (" at " .. path)))
end

local function approved_checked(v, path, err, version)
  if err then
    return M.dialog(v, err)
  end
  store(v, path, version)
end

local function approved(v, path, granted)
  if not granted then
    return M.dialog(v, path .. " was not approved, so the plugin cannot run it")
  end
  Sqlite.version(path, U.bind(approved_checked, v, path))
end

local function request(v, path)
  local ok, err = sys.request_exec(path, U.bind(approved, v, path))
  if not ok then
    M.dialog(v, err)
  end
end

-- ttt's approval dialog cannot open over this one, so it closes first and
-- opens again with the same values when approval is denied or the check fails.
local function checked(v, path, done, err, version, denied)
  if denied and path:sub(1, 1) == "/" and sys.request_exec then
    done()
    return request(v, path)
  end
  if err then
    return done(err)
  end
  store(v, path, version)
  done()
end

local function save(v, done)
  local path = binary_path(v.sqlite3_path)
  if path:sub(1, 1) == "/" and U.basename(path) ~= "sqlite3" then
    return done("The file must be named sqlite3, the name the plugin's manifest allows")
  end
  Sqlite.version(path, U.bind(checked, v, path, done))
end

local function value(v, key, current)
  if v and v[key] ~= nil then
    return v[key]
  end
  return tostring(current)
end

function M.dialog(v, err)
  UI.dialog({
    title = "SQLite Settings",
    width = 80,
    busy_text = "Checking sqlite3…",
    err = err,
    fields = {
      {
        key = "sqlite3_path",
        label = "sqlite3 binary: sqlite3 on PATH, or an absolute path",
        value = value(v, "sqlite3_path", S.binary()),
        placeholder = "sqlite3",
      },
      {
        key = "page_size",
        label = "Page size",
        kind = "enum",
        options = M.PAGE_SIZES,
        value = value(v, "page_size", S.page_size()),
      },
      {
        key = "count_limit_mib",
        label = "Count rows in databases up to (MiB)",
        value = value(v, "count_limit_mib", S.settings.count_limit_mib),
      },
      {
        key = "query_row_limit",
        label = "Query rows kept",
        value = value(v, "query_row_limit", S.settings.query_row_limit),
      },
      {
        key = "query_timeout_s",
        label = "Query timeout",
        kind = "enum",
        options = M.TIMEOUTS,
        value = value(v, "query_timeout_s", S.query_timeout_ms() / 1000),
      },
    },
    on_submit = save,
  })
end

return M
