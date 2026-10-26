local U = require("core.util")
local Router = require("app.router")
local Store = require("features.table.store")
local Data = require("features.table.data")
local Structure = require("features.table.structure")
local Query = require("features.query")

local M = {}

local TABS = { { id = "data", label = "Data" }, { id = "structure", label = "Structure" } }

local function new_query(tv)
  Query.open(tv.db, "SELECT * FROM " .. U.qualified(tv.schema, tv.name) .. " LIMIT 100;")
end

local function actions(tv, h)
  h:button({ label = "Query", on_click = U.bind(new_query, tv) })
  h:button({ label = "Refresh", on_click = U.bind(Store.refresh, tv) })
end

local function render(page, tv, p)
  Store.check_version(tv)
  if Router.tab_strip(p, page, TABS) == "structure" then
    Structure.render(p, tv)
  else
    Data.render(p, tv)
  end
end

local function make_page(db, schema, name, kind)
  local tv = Store.new_view(db, schema, name, kind)
  local page = {
    title = name,
    trail = { db.name, schema },
    tab_title = schema == "main" and name or (schema .. "." .. name),
    db_path = db.path,
  }
  page.render = U.bind(render, page, tv)
  page.actions = U.bind(actions, tv)
  return page
end

function M.open(db, schema, name, kind)
  return Router.show("table:" .. db.path .. "::" .. schema .. "::" .. name, U.bind(make_page, db, schema, name, kind))
end

return M
