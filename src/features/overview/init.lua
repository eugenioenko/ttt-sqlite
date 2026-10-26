local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Db = require("core.db")
local UI = require("components")
local Router = require("app.router")
local Table = require("features.table")
local Query = require("features.query")

-- A database's summary and its tables, in the tab a .db file opens in.
local M = {}

local function objects(st)
  local list = {}
  for _, t in ipairs(st.tables) do
    list[#list + 1] = t
  end
  for _, v in ipairs(st.views) do
    list[#list + 1] = v
  end
  return list
end

local function row_count(st, item)
  if item.type == "view" then
    return ""
  end
  local n = st.counts[item.name]
  return n and U.count(n) or (st.counting and "…" or "")
end

local function open_item(db, list, i)
  local item = list[i]
  if item then
    Table.open(db, db.schema, item.name, item.type)
  end
end

local function select_item(view, i)
  view.sel = i
end

local function objects_table(db, view, st, b)
  local list = objects(st)
  local rows = {}
  for i, item in ipairs(list) do
    rows[i] = { item.name, item.virtual and "virtual table" or item.type, row_count(st, item) }
  end
  b:table({
    inset = 1,
    columns = { { label = "Name" }, { label = "Type", width = 14 }, { label = "Rows", width = 12, align = "right" } },
    rows = rows,
    selected = view.sel,
    loading = st.loading,
    empty = st.err and "Couldn't list tables" or "No tables or views",
    on_select = U.bind(select_item, view),
    on_activate = U.bind(open_item, db, list),
  })
end

local function info_entries(db)
  local info = db.info or {}
  local attached = {}
  for _, a in ipairs(db.attachments) do
    attached[#attached + 1] = a.alias .. " = " .. a.path
  end
  local st = db.objects.main
  return UI.kv({
    { "Path", db.path },
    { "Size", st and st.bytes and U.bytes(st.bytes) or "" },
    { "SQLite", info.version },
    { "Encoding", info.encoding },
    { "Journal mode", info.journal_mode },
    { "Page size", info.page_size and U.bytes(info.page_size) },
    { "User version", info.user_version },
    { "Attached", #attached > 0 and table.concat(attached, ", ") or "none" },
  })
end

local function schema_options(db)
  local options = {}
  for _, s in ipairs(db.schemas) do
    options[#options + 1] = { label = s, value = s }
  end
  return options
end

local function show_sidebar(db)
  S.current = db
  ttt.show_panel("sidebar")
  S.redraw()
end

local function toolbar(db, h)
  h:label({ text = "Schema", style = "muted", padding_left = 1, width = 8 })
  UI.dropdown(h, schema_options(db), db.schema, U.bind(Db.select_schema, db))
  h:label({ text = "" })
  h:button({ label = "New Query", on_click = U.bind(Query.open, db, nil) })
  h:button({ label = "Show in Sidebar", on_click = U.bind(show_sidebar, db) })
  h:button({ label = "Refresh", on_click = U.bind(Db.load, db) })
end

local function retry_row(db, h)
  h:button({ label = "Retry", on_click = U.bind(Db.load, db) })
end

local function render(db, view, p)
  if db.status == "idle" then
    Db.load(db)
  end
  if db.status == "error" then
    p:label({
      text = "✕ " .. U.one_line(db.err or "Could not open the database"),
      style = "danger",
      margin_top = 1,
      padding_left = 1,
    })
    p:hstack({ height = 1, margin_top = 1, padding_left = 1, render = U.bind(retry_row, db) })
    return
  end
  p:keyvalue(info_entries(db))
  if db.err then
    p:label({ text = "! " .. U.one_line(db.err), style = "warning", padding_left = 1 })
  end
  p:hstack({ height = 1, gap = 1, margin_top = 1, render = U.bind(toolbar, db) })
  local st = Db.ensure_objects(db, db.schema)
  UI.frame(p, "Tables and views · " .. db.schema, U.bind(objects_table, db, view, st), { margin_top = 1 })
end

function M.page(db)
  local view = { sel = 1 }
  return {
    title = "Overview",
    trail = { db.name },
    tab_title = db.name,
    db_path = db.path,
    render = U.bind(render, db, view),
  }
end

-- The file handler: a .db file from the explorer opens its overview, and
-- becomes the database the sidebar shows.
function M.open_file(path, tab)
  local db = Db.open(path)
  tab.render = U.bind(Router.render_file, Router.adopt_file(tab.id, M.page(db)))
end

return M
