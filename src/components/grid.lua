local U = require("core.util")
local S = require("core.state")
local R = require("core.results")
local Dialog = require("components.dialog")

-- A page of result rows as a table. ttt's table has no horizontal scroll, so
-- when the columns do not fit, the grid shows a window of them that [ and ]
-- (or the ‹ › buttons) move.
local M = {}

local MAX_COL = 40
local MIN_COL = 4

function M.new_grid()
  return { sel = 1, col = 1 }
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

-- The columns from `first` that fit in avail cells, two cells apart.
local function window(widths, first, avail)
  local last, used = first, widths[first]
  while last < #widths and used + 2 + widths[last + 1] <= avail do
    last = last + 1
    used = used + 2 + widths[last]
  end
  return last
end

local function shift(g, by, count)
  g.col = math.max(1, math.min(g.col + by, count))
  S.redraw()
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

local function detail_body(columns, row, p)
  p:scrollview({ render = U.bind(M.keyvalue_rows, columns, row) })
end

function M.keyvalue_rows(columns, row, p)
  p:keyvalue(detail_entries(columns, row))
end

function M.show_row(title, columns, row)
  if not row then
    return
  end
  Dialog.open_dialog(title, 90, math.min(#columns + 1, 28), U.bind(detail_body, columns, row))
end

local function activate_row(g, opts, i)
  g.sel = i
  local title = (opts.row_title and (opts.row_title .. " · ") or "") .. "Row " .. ((opts.offset or 0) + i)
  M.show_row(title, opts.columns, opts.rows[i])
end

local function grid_command(g, count, cmd, i)
  g.sel = i or g.sel
  if cmd == "prev_cols" then
    shift(g, -1, count)
  elseif cmd == "next_cols" then
    shift(g, 1, count)
  end
end

local function change_page(g, opts, offset)
  g.sel = 1
  opts.on_page(offset)
end

local function nav_buttons(g, first, last, count, h)
  h:button({ label = "‹", style = "bracket", disabled = first <= 1, on_click = U.bind(shift, g, -1, count) })
  h:label({
    text = "Columns " .. first .. "–" .. last .. " of " .. count,
    style = "muted",
    width = U.width("Columns " .. first .. "–" .. last .. " of " .. count),
  })
  h:button({ label = "›", style = "bracket", disabled = last >= count, on_click = U.bind(shift, g, 1, count) })
end

local function footer(g, opts, first, last, h)
  local count = #opts.columns
  if opts.on_page then
    h:pager({
      offset = opts.offset or 0,
      limit = opts.limit or S.page_size(),
      total = opts.total or #opts.rows,
      on_change = U.bind(change_page, g, opts),
    })
  end
  if first > 1 or last < count then
    nav_buttons(g, first, last, count, h)
  end
end

-- opts: columns, numeric, rows (the page), width, offset, limit, total,
-- on_page(offset), loading, empty, row_title.
function M.grid(p, g, opts)
  local columns = opts.columns or {}
  local count = #columns
  if g.col > count then
    g.col = math.max(count, 1)
  end
  local numeric = opts.numeric or {}
  local widths = natural_widths(columns, numeric, opts.rows or {})
  local first = count > 0 and g.col or 1
  local last = count > 0 and window(widths, first, math.max((opts.width or 80) - 3, 10)) or 0
  local cols, rows = {}, {}
  for c = first, last do
    local col = { label = columns[c], align = numeric[c] and "right" or nil }
    if c < last or last < count then
      col.width = widths[c]
    end
    cols[#cols + 1] = col
  end
  for r, row in ipairs(opts.rows or {}) do
    local cells = {}
    for c = first, last do
      cells[#cells + 1] = M.cell(row[c], numeric[c])
    end
    rows[r] = cells
  end
  if #cols == 0 then
    cols = { { label = "" } }
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
    key_commands = { ["["] = "prev_cols", ["]"] = "next_cols" },
    on_command = U.bind(grid_command, g, count),
  })
  p:divider()
  p:hstack({ height = 1, gap = 2, align = "center", render = U.bind(footer, g, opts, first, last) })
end

return M
