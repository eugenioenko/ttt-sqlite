local U = require("core.util")
local S = require("core.state")
local R = require("core.results")
local Sqlite = require("core.sqlite")
local UI = require("components")

-- One table or view's state: its structure, and the page of rows on show.
local M = {}

function M.new_view(db, schema, name, kind)
  return {
    db = db,
    schema = schema,
    name = name,
    kind = kind,
    version = db.version,
    structure = { loaded = false, loading = false, gen = 0 },
    data = {
      loaded = false,
      loading = false,
      gen = 0,
      offset = 0,
      total = 0,
      filter = "",
      draft = "",
      order = "",
      desc = false,
      counted = nil,
    },
    grid = UI.new_grid(),
  }
end

local function structure_sql(tv)
  local name, schema = U.literal(tv.name), U.literal(tv.schema)
  local master = U.ident(tv.schema) .. ".sqlite_master"
  return table.concat({
    "SELECT 'col' AS k, cid, name, type, \"notnull\" AS not_null, dflt_value, pk, hidden FROM pragma_table_xinfo("
      .. name
      .. ", "
      .. schema
      .. ") ORDER BY cid;",
    "SELECT 'idx' AS k, il.seq AS seq, il.name AS name, il.\"unique\" AS uniq, il.origin AS origin, il.partial AS partial,"
      .. " (SELECT group_concat(coalesce(ii.name, '<expr>'), ', ') FROM pragma_index_xinfo(il.name, "
      .. schema
      .. ") ii WHERE ii.key) AS cols,"
      .. " (SELECT m.sql FROM "
      .. master
      .. " m WHERE m.type = 'index' AND m.name = il.name) AS sql"
      .. " FROM pragma_index_list("
      .. name
      .. ", "
      .. schema
      .. ") il ORDER BY il.name;",
    'SELECT \'fk\' AS k, id, seq, "table" AS ref, "from" AS src, "to" AS dst, on_update, on_delete FROM pragma_foreign_key_list('
      .. name
      .. ", "
      .. schema
      .. ") ORDER BY id, seq;",
    "SELECT 'sql' AS k, type, sql FROM " .. master .. " WHERE name = " .. name .. " AND type IN ('table', 'view');",
    "SELECT 'trg' AS k, name, sql FROM "
      .. master
      .. " WHERE type = 'trigger' AND tbl_name = "
      .. name
      .. " ORDER BY name;",
  }, "\n")
end

local function group_fks(rows)
  local fks, by_id = {}, {}
  for _, r in ipairs(rows or {}) do
    local fk = by_id[r.id]
    if not fk then
      fk = { ref = r.ref, src = {}, dst = {}, on_update = r.on_update, on_delete = r.on_delete }
      by_id[r.id] = fk
      fks[#fks + 1] = fk
    end
    fk.src[#fk.src + 1] = r.src or ""
    if r.dst then
      fk.dst[#fk.dst + 1] = r.dst
    end
  end
  return fks
end

local function structure_loaded(tv, gen, err, sets)
  local st = tv.structure
  if gen ~= st.gen then
    return
  end
  local t = R.tagged(sets)
  st.loading = false
  st.loaded = true
  st.err = err
  st.columns = t.col or {}
  st.indexes = t.idx or {}
  st.fks = group_fks(t.fk)
  st.sql = t.sql and t.sql[1] and t.sql[1].sql or ""
  st.triggers = t.trg or {}
  S.redraw()
  M.ensure_data(tv)
end

function M.load_structure(tv)
  local st = tv.structure
  st.gen = st.gen + 1
  st.loading = true
  Sqlite.run(tv.db, structure_sql(tv), {}, U.bind(structure_loaded, tv, st.gen))
end

function M.ensure_structure(tv)
  if not tv.structure.loaded and not tv.structure.loading then
    M.load_structure(tv)
  end
end

-- Blobs show as their size: sqlite3 -json prints their bytes as text.
local function select_list(tv)
  local cols = {}
  for _, c in ipairs(tv.structure.columns or {}) do
    if tonumber(c.hidden) ~= 1 then
      local q = U.ident(c.name)
      cols[#cols + 1] = "CASE WHEN typeof("
        .. q
        .. ") = 'blob' THEN printf('<blob %d bytes>', length("
        .. q
        .. ")) ELSE "
        .. q
        .. " END AS "
        .. q
    end
  end
  if #cols == 0 then
    return "*"
  end
  return table.concat(cols, ", ")
end

local function where(d)
  local f = U.trim(d.filter)
  if f == "" then
    return ""
  end
  return " WHERE " .. f
end

local function data_sql(tv, with_count)
  local d = tv.data
  local from = " FROM " .. U.qualified(tv.schema, tv.name) .. where(d)
  local parts = {}
  if with_count then
    parts[#parts + 1] = "SELECT count(*) AS n" .. from .. ";"
  end
  local order = ""
  if d.order ~= "" then
    order = " ORDER BY " .. U.ident(d.order) .. (d.desc and " DESC" or " ASC")
  end
  parts[#parts + 1] = "SELECT "
    .. select_list(tv)
    .. from
    .. order
    .. " LIMIT "
    .. S.page_size()
    .. " OFFSET "
    .. d.offset
    .. ";"
  return table.concat(parts, "\n")
end

local function data_loaded(tv, gen, with_count, err, sets)
  local d = tv.data
  if gen ~= d.gen then
    return
  end
  d.loading = false
  d.loaded = true
  d.err = err
  local rows_set = sets[1]
  if with_count then
    if sets[1] and not err then
      d.total = tonumber(sets[1].rows[1] and sets[1].rows[1][1]) or 0
      d.counted = d.filter
    end
    rows_set = sets[2]
  end
  if rows_set then
    d.set = rows_set
  else
    d.set = { columns = d.set and d.set.columns or {}, numeric = {}, rows = {} }
  end
  if err then
    d.set.rows = {}
  end
  S.redraw()
end

function M.load_data(tv, recount)
  local d = tv.data
  local with_count = recount or d.counted ~= d.filter
  d.gen = d.gen + 1
  d.loading = true
  Sqlite.run(tv.db, data_sql(tv, with_count), {}, U.bind(data_loaded, tv, d.gen, with_count))
end

function M.ensure_data(tv)
  if tv.structure.loaded and not tv.data.loaded and not tv.data.loading then
    M.load_data(tv)
  end
end

-- Reloads when a query changed the database since this view last loaded.
function M.check_version(tv)
  if tv.version ~= tv.db.version then
    tv.version = tv.db.version
    M.refresh(tv)
  end
end

function M.refresh(tv)
  tv.data.loaded = false
  tv.data.counted = nil
  tv.structure.loaded = false
  M.load_structure(tv)
end

function M.set_page(tv, offset)
  tv.data.offset = offset
  M.load_data(tv)
end

function M.apply_filter(tv, text)
  tv.data.filter = U.trim(text or tv.data.draft)
  tv.data.draft = tv.data.filter
  tv.data.offset = 0
  tv.grid.sel = 1
  M.load_data(tv)
end

function M.set_order(tv, column)
  tv.data.order = column
  tv.data.offset = 0
  M.load_data(tv)
end

function M.toggle_desc(tv)
  tv.data.desc = not tv.data.desc
  tv.data.offset = 0
  if tv.data.order ~= "" then
    M.load_data(tv)
  else
    S.redraw()
  end
end

return M
