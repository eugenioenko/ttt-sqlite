local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")

-- Every table, query and form gets its own editor tab. A tab holds a page:
-- { title, trail?, tab_title?, render(p, tab), actions(h, tab)?, on_key(ev, tab)? };
-- actions draw on the right of the title row.
local M = {}

M.tabs = {}

local function title_row(tab, h)
  local page = tab.page
  local crumbs = {}
  for _, c in ipairs(page.trail or {}) do
    crumbs[#crumbs + 1] = c
  end
  crumbs[#crumbs + 1] = page.title
  h:label({ text = table.concat(crumbs, "  ›  "), style = "bold", padding_left = 1 })
  if page.actions then
    page.actions(h, tab)
  end
end

local function render(tab, p)
  S.panels[tab.id] = p
  tab.panel = p
  p:hstack({ height = 1, gap = 1, render = U.bind(title_row, tab) })
  tab.page.render(p, tab)
end

local function on_event(tab, ev)
  if ev.type == "key" and tab.page.on_key then
    tab.page.on_key(ev, tab)
  end
end

local function forget(tab)
  S.panels[tab.id] = nil
  M.tabs[tab.id] = nil
  if tab.page.on_close then
    tab.page.on_close(tab)
  end
end

-- Opens a page in its own tab keyed by id, or focuses that tab when it is
-- already open (ttt keeps the open tab and ignores the new page).
function M.show(id, make_page)
  local tab = M.tabs[id]
  if not tab then
    tab = { id = id, page = make_page() }
    M.tabs[id] = tab
  end
  ttt.open_tab({
    id = id,
    title = tab.page.tab_title or tab.page.title,
    render = U.bind(render, tab),
    on_event = U.bind(on_event, tab),
    on_close = U.bind(forget, tab),
  })
  return tab
end

function M.close(id)
  ttt.close_tab(id)
end

-- Closes every open tab of a database, for when it is closed.
function M.close_db(path)
  local ids = {}
  for id, tab in pairs(M.tabs) do
    if tab.page.db_path == path then
      ids[#ids + 1] = id
    end
  end
  for _, id in ipairs(ids) do
    ttt.close_tab(id)
  end
end

local function select_tab(page, id)
  page.tab = id
  S.redraw()
end

-- Draws a page's tab strip and returns the active tab id.
function M.tab_strip(p, page, items)
  page.tab = page.tab or items[1].id
  p:tabs({ items = items, active = page.tab, margin_top = 1, on_change = U.bind(select_tab, page) })
  return page.tab
end

-- Renders a file handler's tab with the same title row as router tabs.
function M.render_page(tab, page, p)
  tab.page = page
  render(tab, p)
end

return M
