local U = require("core.util")
local S = require("core.state")
local UI = require("components")
local Router = require("app.router")
local Store = require("features.query.store")

local M = {}

local HINT =
  "Write SQL and press Run or F5. Queries run read-only; one that writes asks first, unless Allow writes is on."

local function sql_input(p, q)
  p:input({
    border = true,
    title = "SQL",
    margin_top = 1,
    multiline = true,
    min_rows = 6,
    max_rows = 12,
    autofocus = true,
    value = q.sql,
    placeholder = "SELECT * FROM sqlite_master;",
    on_change = U.bind(Store.set_sql, q),
  })
end

local function rows_text(q, set)
  local n = #set.rows
  if set.truncated then
    if q.stopped then
      return "first " .. U.count(n) .. " rows shown"
    end
    return "first " .. U.count(n) .. " of " .. U.count(n + set.dropped) .. " rows shown"
  end
  return U.plural(n, "row") .. (q.stopped and " received" or "")
end

local function stats(q)
  if q.running then
    local parts = { U.ms(os.clock() - q.started) }
    if q.received > 0 then
      parts[#parts + 1] = U.plural(q.received, "row") .. " so far"
    end
    return table.concat(parts, " · ")
  end
  if not q.ran then
    return ""
  end
  local parts = {}
  local set = q.sets[q.active]
  if set then
    parts[#parts + 1] = rows_text(q, set)
  elseif not q.stopped and not q.err then
    parts[#parts + 1] = "No rows"
  end
  if q.changes and q.changes > 0 then
    parts[#parts + 1] = U.plural(q.changes, "row") .. " changed"
  end
  parts[#parts + 1] = U.ms(q.elapsed)
  if q.wrote then
    parts[#parts + 1] = "read-write"
  end
  return table.concat(parts, " · ")
end

-- The headline of the last run, when it is not the plain row count.
local function status(q)
  if q.running then
    return "Running…", "muted"
  elseif q.notice then
    return q.notice, "warning"
  elseif q.stopped == "cancelled" then
    return "Cancelled", "warning"
  elseif q.stopped == "timed_out" then
    return "Timed out after " .. U.duration(q.timeout_ms), "danger"
  elseif q.stopped == "truncated" then
    return "Output passed " .. U.bytes(S.OUTPUT_LIMIT) .. ", sqlite3 stopped", "warning"
  elseif q.ran and q.err then
    return "Failed", "danger"
  end
end

local function run(q)
  Store.run(q)
end

local function status_row(q, h)
  local text, style = status(q)
  local detail = stats(q)
  if text then
    h:label({ text = text, style = style, width = U.width(text) })
    detail = detail ~= "" and ("· " .. detail) or ""
  end
  h:label({ text = detail, style = "muted" })
end

local function toolbar(q, h)
  if q.running then
    h:button({ label = "Cancel", on_click = U.bind(Store.cancel, q) })
  else
    h:button({ label = "Run (F5)", on_click = U.bind(run, q) })
  end
  UI.checkbox(h, "Allow writes", q.write, U.bind(Store.set_write, q))
  h:hstack({ height = 1, gap = 1, padding_left = 1, render = U.bind(status_row, q) })
end

local function error_lines(p, q)
  if not q.err then
    return
  end
  for i, line in ipairs(U.lines(q.err)) do
    UI.message(p, line, "danger", { prefix = i == 1 and "✕ " or "  ", margin_top = i == 1 and 1 or nil })
  end
end

local function set_tabs(p, q)
  local items = {}
  for i, set in ipairs(q.sets) do
    items[i] = { id = tostring(i), label = "Result " .. i .. " (" .. #set.rows .. ")" }
  end
  p:tabs({ items = items, active = tostring(q.active), margin_top = 1, on_change = U.bind(Store.select_set, q) })
end

local function page_rows(rows, offset, limit)
  local out = {}
  for i = offset + 1, math.min(offset + limit, #rows) do
    out[#out + 1] = rows[i]
  end
  return out
end

local function grid_box(q, b)
  local set = q.sets[q.active] or { columns = {}, numeric = {}, rows = {} }
  local limit = S.page_size()
  UI.grid(b, q.grid, {
    columns = set.columns,
    numeric = set.numeric,
    rows = page_rows(set.rows, q.offset, limit),
    offset = q.offset,
    limit = limit,
    total = #set.rows,
    on_page = U.bind(Store.set_page, q),
    loading = q.running,
    empty = q.err and "No results" or "The query returned no rows",
    row_title = "Query " .. q.n,
  })
end

local function results(p, q)
  if not q.ran and not q.running and not q.notice then
    p:label({ text = HINT, style = "muted", margin_top = 1, padding_left = 1 })
    return
  end
  for _, note in ipairs(q.notes or {}) do
    p:label({ text = note, style = "muted", padding_left = 1 })
  end
  if #q.sets > 1 then
    set_tabs(p, q)
  end
  UI.frame(p, "Results", U.bind(grid_box, q), { margin_top = #q.sets > 1 and 0 or 1 })
end

local function render(q, p)
  sql_input(p, q)
  p:hstack({ height = 1, gap = 2, margin_top = 1, render = U.bind(toolbar, q) })
  error_lines(p, q)
  results(p, q)
end

local function on_key(q, ev)
  if ev.key == "F5" then
    Store.run(q)
  end
end

local function make_page(q)
  return {
    on_close = U.bind(Store.dispose, q),
    title = "Query " .. q.n,
    trail = { q.db.name },
    tab_title = "Query " .. q.n .. " · " .. q.db.name,
    db_path = q.db.path,
    render = U.bind(render, q),
    on_key = U.bind(on_key, q),
  }
end

function M.open(db, sql)
  if not db then
    return false
  end
  local q = Store.new_query(db, sql)
  Router.show("query:" .. q.n, U.bind(make_page, q))
  return true
end

return M
