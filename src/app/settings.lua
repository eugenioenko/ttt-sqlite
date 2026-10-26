local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Sqlite = require("core.sqlite")
local UI = require("components")

local M = {}

M.PAGE_SIZES = {
  { label = "25 rows per page", value = "25" },
  { label = "50 rows per page", value = "50" },
  { label = "100 rows per page", value = "100" },
  { label = "200 rows per page", value = "200" },
}

local function checked(old, v, done, err, version)
  if err then
    S.settings.sqlite3_path = old
    return done(err)
  end
  S.settings.page_size = tonumber(v.page_size) or S.DEFAULTS.page_size
  S.settings.count_limit_mib = tonumber(v.count_limit_mib) or S.DEFAULTS.count_limit_mib
  S.settings.query_row_limit = tonumber(v.query_row_limit) or S.DEFAULTS.query_row_limit
  S.save_settings()
  ttt.notify("Using sqlite3 " .. version)
  done()
end

-- The binary is checked with -version before anything is saved; Sqlite reads
-- the path from settings, so it is set first and put back on failure.
local function save(v, done)
  local old = S.settings.sqlite3_path
  local path = U.trim(v.sqlite3_path)
  S.settings.sqlite3_path = path ~= "" and path or S.DEFAULTS.sqlite3_path
  Sqlite.version(U.bind(checked, old, v, done))
end

function M.dialog()
  UI.dialog({
    title = "SQLite Settings",
    width = 80,
    busy_text = "Checking sqlite3…",
    fields = {
      { key = "sqlite3_path", label = "sqlite3 binary", value = S.binary(), placeholder = "sqlite3" },
      {
        key = "page_size",
        label = "Page size",
        kind = "enum",
        options = M.PAGE_SIZES,
        value = tostring(S.page_size()),
      },
      {
        key = "count_limit_mib",
        label = "Count rows in databases up to (MiB)",
        value = tostring(S.settings.count_limit_mib),
      },
      { key = "query_row_limit", label = "Query rows kept", value = tostring(S.settings.query_row_limit) },
    },
    on_submit = save,
  })
end

return M
