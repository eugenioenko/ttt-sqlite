local ttt = require("ttt")
local S = require("core.state")
local Db = require("core.db")
local Router = require("app.router")
local Sidebar = require("app.sidebar")
local Open = require("app.open")
local Attach = require("app.attach")
local Settings = require("app.settings")
local Query = require("features.query")
local Overview = require("features.overview")

local function new_query()
  if not Query.open(S.current) then
    Open.dialog()
  end
end

local function refresh()
  if S.current then
    Db.load(S.current)
  end
end

local function close_database()
  local db = S.current
  if db then
    Router.close_db(db.path)
    Db.close(db)
  end
end

local function show_panel()
  ttt.focus_panel("sidebar")
end

local actions = {
  open = Open.dialog,
  query = new_query,
  attach = Attach.dialog,
  detach = Attach.detach_current,
  refresh = refresh,
  close = close_database,
  settings = Settings.dialog,
}

local function on_action(cmd)
  local run = actions[cmd]
  if run then
    run()
  end
end

ttt.register({
  sidebar = {
    title = "SQLite",
    render = Sidebar.render,
    actions = {
      { label = "Open Database…", command = "open" },
      { label = "New Query", command = "query" },
      { separator = true },
      { label = "Attach Database…", command = "attach" },
      { label = "Detach Schema", command = "detach" },
      { label = "Refresh", command = "refresh" },
      { label = "Close Database", command = "close" },
      { separator = true },
      { label = "Settings…", command = "settings" },
    },
    on_action = on_action,
  },
  commands = {
    { id = "sqlite.openDatabase", title = "SQLite: Open Database…", handler = Open.dialog },
    { id = "sqlite.newQuery", title = "SQLite: New Query", handler = new_query },
    { id = "sqlite.attachDatabase", title = "SQLite: Attach Database…", handler = Attach.dialog },
    { id = "sqlite.detachSchema", title = "SQLite: Detach Schema", handler = Attach.detach_current },
    { id = "sqlite.refresh", title = "SQLite: Refresh", handler = refresh },
    { id = "sqlite.closeDatabase", title = "SQLite: Close Database", handler = close_database },
    { id = "sqlite.showPanel", title = "SQLite: Show Panel", handler = show_panel },
    { id = "sqlite.settings", title = "SQLite: Settings…", handler = Settings.dialog },
  },
  file_handlers = {
    {
      id = "sqlite",
      title = "SQLite",
      extensions = { "sqlite", "sqlite3", "db" },
      magic = "SQLite format 3\0",
      open = Overview.open_file,
    },
  },
})
