local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local R = require("core.results")
local Sqlite = require("core.sqlite")

-- An open database file: its attached databases (schemas), and per schema the
-- tables and views, loaded on demand. `version` goes up whenever a write may
-- have changed what is in it, so open views know to reload.
local M = {}

local function new_db(path)
  return {
    path = path,
    name = U.basename(path),
    attachments = S.attachments(path),
    schemas = { "main", "temp" },
    files = {},
    schema = "main",
    objects = {},
    info = nil,
    status = "idle",
    err = nil,
    version = 0,
    gen = 0,
  }
end

function M.get(path)
  local db = S.dbs[path]
  if not db then
    db = new_db(path)
    S.dbs[path] = db
  end
  return db
end

function M.open(path)
  local db = M.get(path)
  S.current = db
  S.remember(path)
  if db.status == "idle" or db.status == "error" then
    M.load(db)
  end
  S.redraw()
  return db
end

function M.close(db)
  if S.current == db then
    S.current = nil
  end
  S.dbs[db.path] = nil
  S.redraw()
end

function M.schema_state(db, schema)
  local st = db.objects[schema]
  if not st then
    st = { tables = {}, views = {}, counts = {}, loading = false, loaded = false, err = nil, gen = 0 }
    db.objects[schema] = st
  end
  return st
end

local INFO_SQL = [[
SELECT 'schema' AS k, name, file FROM pragma_database_list ORDER BY seq;
SELECT 'info' AS k, sqlite_version() AS version,
  (SELECT encoding FROM pragma_encoding) AS encoding,
  (SELECT journal_mode FROM pragma_journal_mode) AS journal_mode,
  (SELECT page_size FROM pragma_page_size) AS page_size,
  (SELECT user_version FROM pragma_user_version) AS user_version;]]

local function info_loaded(db, gen, err, sets)
  if gen ~= db.gen then
    return
  end
  local t = R.tagged(sets)
  if not t.info then
    db.status = "error"
    db.err = err or "Could not read the database"
    S.redraw()
    return
  end
  db.status = "ok"
  db.err = err
  db.info = t.info[1]
  local schemas, files = { "main", "temp" }, { main = db.path }
  for _, rec in ipairs(t.schema or {}) do
    if rec.name ~= "main" and rec.name ~= "temp" then
      schemas[#schemas + 1] = rec.name
    end
    files[rec.name] = rec.file
  end
  for _, a in ipairs(db.attachments) do
    if not files[a.alias] then
      schemas[#schemas + 1] = a.alias
    end
  end
  db.schemas = schemas
  db.files = files
  local valid = false
  for _, s in ipairs(schemas) do
    valid = valid or s == db.schema
  end
  if not valid then
    db.schema = "main"
  end
  M.load_objects(db, db.schema)
  S.redraw()
end

-- Reloads what the database holds: its schemas, then the selected schema's
-- tables and views.
function M.load(db)
  db.gen = db.gen + 1
  db.status = "loading"
  db.objects = {}
  Sqlite.run(db, INFO_SQL, {}, U.bind(info_loaded, db, db.gen))
end

local function size_sql(schema)
  local lit = U.literal(schema)
  return "SELECT 'size' AS k, (SELECT page_count FROM pragma_page_count("
    .. lit
    .. ")) * (SELECT page_size FROM pragma_page_size("
    .. lit
    .. ")) AS bytes;"
end

local function objects_sql(schema)
  return "SELECT 'obj' AS k, name, type, sql FROM "
    .. U.ident(schema)
    .. ".sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite!_%' ESCAPE '!' ORDER BY name;\n"
    .. size_sql(schema)
end

local function counts_loaded(db, st, gen, _, sets)
  if gen ~= st.gen then
    return
  end
  for _, rec in ipairs(R.tagged(sets).count or {}) do
    st.counts[rec.name] = tonumber(rec.n)
  end
  st.counting = false
  S.redraw()
end

local function count_tables(db, schema, st)
  local parts = {}
  for _, t in ipairs(st.tables) do
    if not t.virtual then
      parts[#parts + 1] = "SELECT 'count' AS k, "
        .. U.literal(t.name)
        .. " AS name, count(*) AS n FROM "
        .. U.qualified(schema, t.name)
        .. ";"
    end
  end
  if #parts == 0 then
    return
  end
  st.counting = true
  Sqlite.run(db, table.concat(parts, "\n"), { bail = false }, U.bind(counts_loaded, db, st, st.gen))
end

local function objects_loaded(db, schema, st, gen, err, sets)
  if gen ~= st.gen then
    return
  end
  st.loading = false
  st.loaded = true
  local t = R.tagged(sets)
  if err and not t.obj then
    st.err = err
  end
  st.tables, st.views = {}, {}
  for _, rec in ipairs(t.obj or {}) do
    local item = { name = rec.name, type = rec.type, sql = rec.sql }
    if rec.type == "view" then
      st.views[#st.views + 1] = item
    else
      item.virtual = (rec.sql or ""):upper():find("^%s*CREATE%s+VIRTUAL") ~= nil
      st.tables[#st.tables + 1] = item
    end
  end
  st.bytes = t.size and tonumber(t.size[1].bytes)
  if st.bytes and st.bytes <= (tonumber(S.settings.count_limit_mib) or 0) * 1024 * 1024 then
    count_tables(db, schema, st)
  end
  S.redraw()
end

function M.load_objects(db, schema)
  local st = M.schema_state(db, schema)
  st.gen = st.gen + 1
  st.loading = true
  st.err = nil
  st.counts = {}
  Sqlite.run(db, objects_sql(schema), {}, U.bind(objects_loaded, db, schema, st, st.gen))
  return st
end

function M.ensure_objects(db, schema)
  local st = M.schema_state(db, schema)
  if not st.loaded and not st.loading and db.status == "ok" then
    M.load_objects(db, schema)
  end
  return st
end

function M.select_schema(db, schema)
  db.schema = schema
  M.ensure_objects(db, schema)
  S.redraw()
end

-- After a query that may have written: reload everything that is cached.
function M.changed(db)
  db.version = db.version + 1
  M.load(db)
end

function M.find(db, schema, name)
  local st = db.objects[schema]
  if not st then
    return nil
  end
  for _, list in ipairs({ st.tables, st.views }) do
    for _, item in ipairs(list) do
      if item.name == name then
        return item
      end
    end
  end
end

function M.attach(db, path, alias)
  for _, a in ipairs(db.attachments) do
    if a.alias:lower() == alias:lower() then
      return "A database is already attached as " .. alias
    end
  end
  table.insert(db.attachments, { path = path, alias = alias })
  S.save_attachments(db.path, db.attachments)
  db.schema = alias
  M.load(db)
  ttt.notify("Attached " .. U.basename(path) .. " as " .. alias)
end

function M.detach(db, alias)
  local list = {}
  for _, a in ipairs(db.attachments) do
    if a.alias ~= alias then
      list[#list + 1] = a
    end
  end
  db.attachments = list
  S.save_attachments(db.path, list)
  if db.schema == alias then
    db.schema = "main"
  end
  M.load(db)
  ttt.notify("Detached " .. alias)
end

function M.is_attached(db, schema)
  for _, a in ipairs(db.attachments) do
    if a.alias == schema then
      return true
    end
  end
  return false
end

return M
