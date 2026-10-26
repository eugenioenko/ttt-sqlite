local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local R = require("core.results")
local Dialog = require("components.dialog")

local M = {}

local MAX_COL = 40
local MIN_COL = 4

local ACTIONS = { label = "", actions = { { label = "View", command = "view" } } }

function M.new_grid()
  return { sel = 1 }
end

-- sqlite3 -json prints reals with 17 digits (864.7859999999999); the row
-- dialog keeps them exact, the grid shows them like sqlite3's other modes.
function M.cell(v, numeric)
  if v == nil or v == R.NULL then
    return "NULL"
  end
  if numeric and v:find("[%.eE]") then
    local n = tonumber(v)
    if n then
      return string.format("%.15g", n)
    end
  end
  return U.clip(U.one_line(v), 200)
end

local function natural_widths(columns, numeric, rows)
  local widths = {}
  for c, name in ipairs(columns) do
    local w = U.width(name)
    for _, row in ipairs(rows) do
      w = math.max(w, U.width(M.cell(row[c], numeric[c])))
      if w >= MAX_COL then
        break
      end
    end
    widths[c] = math.max(MIN_COL, math.min(w, MAX_COL))
  end
  return widths
end

local function select_row(g, i)
  g.sel = i
end

local function detail_entries(columns, row)
  local out = { padding_left = 1, muted_keys = true }
  for c, name in ipairs(columns) do
    local v = row[c]
    out[#out + 1] = { key = name, value = (v == nil or v == R.NULL) and "NULL" or U.one_line(v) }
  end
  return out
end

local function close_button(h)
  h:button({ label = "Close", style = "bracket", on_click = ttt.close_dialog })
end

local function detail_body(columns, row, rows, p)
  p:scrollview({ height = rows, render = U.bind(M.keyvalue_rows, columns, row) })
  p:hstack({ height = 1, margin_top = 1, align = "right", render = close_button })
end

function M.keyvalue_rows(columns, row, p)
  p:keyvalue(detail_entries(columns, row))
end

function M.show_row(title, columns, row)
  if not row then
    return
  end
  local rows = math.min(#columns + 1, 26)
  Dialog.open_dialog(title, 90, rows + 2, U.bind(detail_body, columns, row, rows))
end

local function activate_row(g, opts, i)
  g.sel = i
  local title = (opts.row_title and (opts.row_title .. " · ") or "") .. "Row " .. ((opts.offset or 0) + i)
  M.show_row(title, opts.columns, opts.rows[i])
end

local function row_command(g, opts, cmd, i)
  if cmd == "view" then
    activate_row(g, opts, i)
  end
end

local function change_page(g, opts, offset)
  g.sel = 1
  opts.on_page(offset)
end

local function footer(g, opts, h)
  h:pager({
    offset = opts.offset or 0,
    limit = opts.limit or S.page_size(),
    total = opts.total or #opts.rows,
    on_change = U.bind(change_page, g, opts),
  })
end

-- opts: columns, numeric, rows (the page), offset, limit, total,
-- on_page(offset), loading, empty, row_title.
function M.grid(p, g, opts)
  local columns = opts.columns or {}
  local count = #columns
  local numeric = opts.numeric or {}
  local widths = natural_widths(columns, numeric, opts.rows or {})
  local cols, rows = {}, {}
  for c = 1, count do
    local col = { label = columns[c], align = numeric[c] and "right" or nil }
    if c < count then
      col.width = widths[c]
    else
      col.min_width = widths[c]
    end
    cols[c] = col
  end
  for r, row in ipairs(opts.rows or {}) do
    local cells = {}
    for c = 1, count do
      cells[c] = M.cell(row[c], numeric[c])
    end
    rows[r] = cells
  end
  if count == 0 then
    cols = { { label = "" } }
  else
    cols[count + 1] = ACTIONS
  end
  if g.sel > #rows then
    g.sel = math.max(#rows, 1)
  end
  p:table({
    inset = 1,
    columns = cols,
    rows = rows,
    selected = g.sel,
    loading = opts.loading,
    empty = opts.empty or "No rows",
    on_select = U.bind(select_row, g),
    on_activate = U.bind(activate_row, g, opts),
    on_command = U.bind(row_command, g, opts),
  })
  if opts.on_page then
    p:divider()
    p:hstack({ height = 1, gap = 2, align = "center", render = U.bind(footer, g, opts) })
  end
end

return M
