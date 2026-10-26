local U = require("core.util")
local S = require("core.state")
local UI = require("components")
local Store = require("features.table.store")

local M = {}

local function set_draft(tv, text)
  tv.data.draft = text
end

local function order_options(tv)
  local options = { { label = "Default order", value = "" } }
  for _, c in ipairs(tv.structure.columns or {}) do
    if tonumber(c.hidden) ~= 1 then
      options[#options + 1] = { label = "Order by " .. c.name, value = c.name }
    end
  end
  return options
end

local function filter_input(p, tv)
  p:input({
    border = true,
    margin_top = 1,
    title = "Filter",
    prefix = "WHERE ",
    placeholder = "SQL condition, Enter to apply",
    value = tv.data.draft,
    on_change = U.bind(set_draft, tv),
    on_submit = U.bind(Store.apply_filter, tv),
  })
end

local function order_row(tv, h)
  UI.dropdown(h, order_options(tv), tv.data.order, U.bind(Store.set_order, tv))
  h:button({
    label = tv.data.desc and "↓ Descending" or "↑ Ascending",
    style = "bracket",
    disabled = tv.data.order == "",
    on_click = U.bind(Store.toggle_desc, tv),
  })
end

local function column_names(tv)
  local names, numeric = {}, {}
  for _, c in ipairs(tv.structure.columns or {}) do
    if tonumber(c.hidden) ~= 1 then
      names[#names + 1] = c.name
    end
  end
  return names, numeric
end

local function status_text(tv)
  local d = tv.data
  if d.loading then
    return "Loading…", "muted"
  end
  if d.err then
    return "✕ " .. U.one_line(d.err), "danger"
  end
  local text = U.plural(d.total, "row")
  if d.filter ~= "" then
    text = text .. " match the filter"
  end
  return text, "muted"
end

local function grid_box(tv, width, b)
  local d = tv.data
  local set = d.set or {}
  local columns, numeric = set.columns, set.numeric
  if not columns or #columns == 0 then
    columns, numeric = column_names(tv)
  end
  UI.grid(b, tv.grid, {
    columns = columns,
    numeric = numeric,
    rows = set.rows or {},
    width = width - 2,
    offset = d.offset,
    limit = S.page_size(),
    total = d.total,
    on_page = U.bind(Store.set_page, tv),
    loading = d.loading,
    empty = d.err and "Couldn't load rows" or (d.filter ~= "" and "No rows match the filter" or "No rows"),
    row_title = tv.name,
  })
end

local function status_row(tv, h)
  local text, style = status_text(tv)
  h:label({ text = text, style = style, padding_left = 1 })
  order_row(tv, h)
end

function M.render(p, tv)
  Store.ensure_structure(tv)
  Store.ensure_data(tv)
  local width = p:size()
  filter_input(p, tv)
  p:hstack({ height = 1, gap = 1, render = U.bind(status_row, tv) })
  if tv.structure.err then
    p:label({ text = "! " .. U.one_line(tv.structure.err), style = "warning", padding_left = 1 })
  end
  UI.frame(p, "Rows", U.bind(grid_box, tv, width))
end

return M
