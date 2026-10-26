local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Db = require("core.db")
local UI = require("components")
local Open = require("app.open")
local Attach = require("app.attach")
local Table = require("features.table")
local Query = require("features.query")

local M = {}

local function open_failed(err)
  if err then
    ttt.notify(err, "error")
  end
end

local function open_object(db, node)
  local kind = node.id:sub(1, 1) == "v" and "view" or "table"
  Table.open(db, db.schema, node.id:sub(3), kind)
end

local function link(db, node)
  if node.id == "open" then
    Open.dialog()
  elseif node.id == "query" then
    Query.open(db)
  elseif node.id == "attach" then
    Attach.dialog(db)
  elseif node.id:sub(1, 7) == "recent:" then
    Open.open_path(node.id:sub(8), open_failed)
  elseif db then
    open_object(db, node)
  end
end

-- "activate" comes on every click and Enter, also for the row that is already
-- selected, which on_select misses on older ttt; arrowing only moves.
local function on_command(db, command, node)
  if command == "activate" then
    link(db, node)
  elseif command == "query" and db and node.id:sub(2, 2) == ":" then
    Query.open(db, "SELECT * FROM " .. U.qualified(db.schema, node.id:sub(3)) .. " LIMIT 100;")
  end
end

local OBJECT_MENU = {
  { label = "Open", command = "activate" },
  { label = "Query", command = "query" },
}

local function link_list(db, items, menu, b)
  b:list({
    items = items,
    inset = 1,
    badge_right = true,
    node_menu = menu,
    on_command = U.bind(on_command, db),
  })
end

local function links(p, db, items, menu)
  p:box({ height = math.max(#items, 1), render = U.bind(link_list, db, items, menu) })
end

local function badge(st, t)
  if t.virtual then
    return "virtual"
  end
  local n = st.counts[t.name]
  if n then
    return U.count(n)
  end
  return st.counting and "…" or nil
end

local function object_items(st, list, prefix)
  local items = {}
  for i, t in ipairs(list) do
    items[i] = {
      id = prefix .. ":" .. t.name,
      label = t.name,
      badge = prefix == "v" and "view" or badge(st, t),
    }
  end
  return items
end

local function section(p, db, title, items, empty)
  p:label({ text = "• " .. title, style = "muted", margin_top = 1, padding_left = 1 })
  if #items == 0 then
    p:label({ text = empty, style = "muted", padding_left = 3 })
    return
  end
  links(p, db, items, OBJECT_MENU)
end

local function schema_options(db)
  local options = {}
  for _, s in ipairs(db.schemas) do
    options[#options + 1] = { label = s, value = s }
  end
  return options
end

local function schema_row(db, h)
  h:label({ text = "Schema", style = "muted", padding_left = 1, width = 8 })
  UI.dropdown(h, schema_options(db), db.schema, U.bind(Db.select_schema, db))
end

local function objects(p, db)
  local st = Db.ensure_objects(db, db.schema)
  if st.loading and not st.loaded then
    p:label({ text = "Loading…", style = "muted", margin_top = 1, padding_left = 1 })
    return
  end
  if st.err then
    p:label({ text = "✕ " .. U.one_line(st.err), style = "danger", margin_top = 1, padding_left = 1 })
    return
  end
  section(p, db, "TABLES", object_items(st, st.tables, "t"), "No tables")
  section(p, db, "VIEWS", object_items(st, st.views, "v"), "No views")
  if db.schema == "temp" then
    p:label({ text = "temp is empty here: every", style = "muted", margin_top = 1, padding_left = 1 })
    p:label({ text = "query runs a new sqlite3.", style = "muted", padding_left = 1 })
  end
end

local function recent(p)
  local items = {}
  for i, path in ipairs(S.recent) do
    if i > 6 then
      break
    end
    items[#items + 1] =
      { id = "recent:" .. path, label = U.basename(path), badge = U.basename(path:match("(.*)/") or "") }
  end
  if #items == 0 then
    return
  end
  p:label({ text = "• RECENT", style = "muted", margin_top = 1, padding_left = 1 })
  links(p, nil, items)
end

local function no_database(p)
  p:label({ text = "No database open.", style = "muted", margin_top = 1, padding_left = 1 })
  links(p, nil, { { id = "open", label = "Open Database…" } })
  recent(p)
end

local function database(p, db)
  local status = db.status == "loading" and "…" or nil
  p:label({ text = " " })
  p:box({
    height = 1,
    render = U.bind(link_list, db, { { id = "open", label = "◆ " .. db.name, badge = status } }, nil),
  })
  if db.status == "error" then
    p:label({ text = "✕ " .. U.one_line(db.err or "Could not open"), style = "danger", padding_left = 1 })
    return
  end
  if db.err then
    p:label({ text = "! " .. U.one_line(db.err), style = "warning", padding_left = 1 })
  end
  p:hstack({ height = 1, margin_top = 1, render = U.bind(schema_row, db) })
  if db.status == "ok" then
    objects(p, db)
  end
end

local function body(db, p)
  database(p, db)
  p:divider()
  links(p, db, {
    { id = "query", label = "New Query" },
    { id = "attach", label = "Attach Database…" },
  })
end

function M.render(p)
  S.panels.sidebar = p
  local db = S.current
  if not db then
    no_database(p)
    return
  end
  p:scrollview({ render = U.bind(body, db) })
end

return M
