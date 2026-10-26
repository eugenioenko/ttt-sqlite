local ttt = require("ttt")
local U = require("core.util")
local UI = require("components")
local Store = require("features.table.store")

local M = {}

local ORIGINS = { c = "index", u = "unique constraint", pk = "primary key" }
local HIDDEN = { ["1"] = "hidden", ["2"] = "generated (virtual)", ["3"] = "generated (stored)" }

local function yes(v)
  return tonumber(v) and tonumber(v) ~= 0 and "yes" or ""
end

local function column_rows(st)
  local rows = {}
  for i, c in ipairs(st.columns or {}) do
    local pk = tonumber(c.pk) or 0
    rows[i] = {
      tostring(i),
      c.name or "",
      c.type or "",
      yes(c.not_null),
      c.dflt_value or "",
      pk > 0 and tostring(pk) or "",
      HIDDEN[tostring(c.hidden)] or "",
    }
  end
  return rows
end

local COLUMN_COLS = {
  { label = "#", width = 3, align = "right" },
  { label = "Name" },
  { label = "Type", width = 14 },
  { label = "Not null", width = 8 },
  { label = "Default" },
  { label = "PK", width = 3, align = "right" },
  { label = "Notes", width = 20 },
}

local function index_rows(st)
  local rows = {}
  for i, x in ipairs(st.indexes or {}) do
    rows[i] = {
      x.name or "",
      x.cols or "",
      yes(x.uniq),
      ORIGINS[x.origin] or x.origin or "",
      yes(x.partial),
    }
  end
  return rows
end

local INDEX_COLS = {
  { label = "Name" },
  { label = "Columns" },
  { label = "Unique", width = 6 },
  { label = "Origin", width = 17 },
  { label = "Partial", width = 7 },
}

local function fk_rows(st)
  local rows = {}
  for i, fk in ipairs(st.fks or {}) do
    local target = fk.ref .. (#fk.dst > 0 and ("(" .. table.concat(fk.dst, ", ") .. ")") or "")
    rows[i] = { table.concat(fk.src, ", "), target, fk.on_update or "", fk.on_delete or "" }
  end
  return rows
end

local FK_COLS = {
  { label = "Columns" },
  { label = "References" },
  { label = "On update", width = 11 },
  { label = "On delete", width = 11 },
}

local function trigger_rows(st)
  local rows = {}
  for i, t in ipairs(st.triggers or {}) do
    rows[i] = { t.name or "", U.clip(U.one_line(t.sql or ""), 120) }
  end
  return rows
end

local TRIGGER_COLS = { { label = "Name", width = 28 }, { label = "Definition" } }

local function table_body(cols, rows, empty, b)
  b:table({ inset = 1, columns = cols, rows = rows, empty = empty })
end

local function section(p, title, cols, rows, empty)
  local height = math.max(#rows, 1) + 5
  UI.frame(p, title .. " (" .. #rows .. ")", U.bind(table_body, cols, rows, empty), { height = height, margin_top = 1 })
end

local function sql_text(tv)
  local st = tv.structure
  local parts = { st.sql ~= "" and (table.concat(U.format_create(st.sql), "\n") .. ";") or "" }
  for _, x in ipairs(st.indexes or {}) do
    if x.sql then
      parts[#parts + 1] = x.sql .. ";"
    end
  end
  for _, t in ipairs(st.triggers or {}) do
    if t.sql then
      parts[#parts + 1] = t.sql .. ";"
    end
  end
  return table.concat(parts, "\n\n")
end

local function open_sql(tv)
  ttt.open_readonly(tv.name .. ".sql", U.lines(sql_text(tv)), tv.name .. ".sql")
end

local function sql_body(tv, width, b)
  for _, line in ipairs(U.format_create(tv.structure.sql)) do
    for _, part in ipairs(U.wrap(line, math.max(width - 6, 20))) do
      b:label({ text = part == "" and " " or part, style = "code", padding_left = 1 })
    end
  end
end

local function sql_actions(tv, h)
  h:label({ text = "" })
  h:button({ label = "Open as SQL", on_click = U.bind(open_sql, tv) })
end

local function body(tv, width, p)
  local st = tv.structure
  section(p, "Columns", COLUMN_COLS, column_rows(st), "No columns")
  if tv.kind ~= "view" then
    section(p, "Indexes", INDEX_COLS, index_rows(st), "No indexes")
    section(p, "Foreign keys", FK_COLS, fk_rows(st), "No foreign keys")
  end
  if #(st.triggers or {}) > 0 then
    section(p, "Triggers", TRIGGER_COLS, trigger_rows(st), "")
  end
  UI.frame(p, "CREATE statement", U.bind(sql_body, tv, width), { margin_top = 1 })
  p:hstack({ height = 1, margin_top = 1, render = U.bind(sql_actions, tv) })
end

function M.render(p, tv)
  Store.ensure_structure(tv)
  local st = tv.structure
  if not st.loaded then
    p:label({ text = "Loading structure…", style = "muted", margin_top = 1, padding_left = 1 })
    return
  end
  if st.err then
    p:label({ text = "✕ " .. U.one_line(st.err), style = "danger", margin_top = 1, padding_left = 1 })
  end
  p:scrollview({ render = U.bind(body, tv, (p:size())) })
end

return M
