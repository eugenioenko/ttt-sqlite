local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Db = require("core.db")
local Sqlite = require("core.sqlite")
local UI = require("components")
local Paths = require("app.paths")

-- ATTACH lasts as long as one sqlite3 process, and every query runs in a new
-- one, so the plugin keeps the list per database and attaches it each time.
local M = {}

local function default_alias(path)
  local alias = U.stem(path):gsub("[^%w_]", "_")
  if alias:find("^%d") then
    alias = "db_" .. alias
  end
  return alias
end

local function checked(db, path, alias, done, err)
  if err then
    if err:find("not a database", 1, true) then
      err = U.basename(path) .. " is not an SQLite database"
    elseif err:find("unable to open", 1, true) then
      err = "Cannot open " .. path
    end
    return done(err)
  end
  local fail = Db.attach(db, path, alias)
  done(fail)
end

local function submit(db, v, done)
  local path = Paths.normalize(v.path)
  local alias = U.trim(v.alias)
  if alias == "" then
    alias = default_alias(path)
  end
  local lower = alias:lower()
  if lower == "main" or lower == "temp" then
    return done("main and temp are reserved names")
  end
  local probe = { path = path, attachments = {} }
  Sqlite.run(probe, "SELECT count(*) AS n FROM sqlite_master;", {}, U.bind(checked, db, path, alias, done))
end

function M.dialog(db)
  db = db or S.current
  if not db then
    ttt.notify("Open a database first", "warn")
    return
  end
  UI.dialog({
    title = "Attach Database to " .. db.name,
    submit = "Attach",
    busy_text = "Attaching…",
    width = 70,
    fields = {
      { key = "path", label = "Database file", required = true, placeholder = "~/data/archive.db" },
      { key = "alias", label = "Schema name", placeholder = "defaults to the file name" },
    },
    on_submit = U.bind(submit, db),
  })
end

local function detach(db, alias)
  Db.detach(db, alias)
end

function M.detach_current(db)
  db = db or S.current
  if not db or not Db.is_attached(db, db.schema) then
    ttt.notify("Select an attached schema to detach", "warn")
    return
  end
  ttt.confirm("Detach " .. db.schema .. " from " .. db.name .. "?", U.bind(detach, db, db.schema))
end

return M
