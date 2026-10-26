local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Sqlite = require("core.sqlite")
local Db = require("core.db")
local UI = require("components")

local M = {}

local MARK = "__ttt_sqlite_changes"

M.count = 0

function M.new_query(db, sql)
  M.count = M.count + 1
  return {
    n = M.count,
    db = db,
    sql = sql or "",
    write = false,
    running = false,
    ran = false,
    err = nil,
    sets = {},
    active = 1,
    offset = 0,
    grid = UI.new_grid(),
    gen = 0,
  }
end

-- sqlite3 prints nothing for statements without rows, so a trailing
-- total_changes() tells a write that changed nothing from one that did.
local function script(sql)
  return sql .. "\n;\nSELECT total_changes() AS " .. MARK .. ";"
end

local function split_changes(sets)
  local last = sets[#sets]
  if last and #last.columns == 1 and last.columns[1] == MARK then
    table.remove(sets)
    return tonumber(last.rows[1] and last.rows[1][1])
  end
  return nil
end

local function stop_ticker(q)
  if q.ticker then
    ttt.clear_interval(q.ticker)
    q.ticker = nil
  end
end

local function received(q, gen, sets)
  if gen ~= q.gen then
    return
  end
  local n = 0
  for _, set in ipairs(sets) do
    if set.columns[1] ~= MARK then
      n = n + #set.rows + set.dropped
    end
  end
  q.received = n
end

local function stop_reason(info)
  if info.cancelled then
    return "cancelled"
  elseif info.timed_out then
    return "timed_out"
  elseif info.truncated then
    return "truncated"
  end
end

local function finished(q, gen, write, err, sets, info)
  if gen ~= q.gen then
    return
  end
  q.running = false
  q.job = nil
  stop_ticker(q)
  local stopped = stop_reason(info)
  if not write and not stopped and Sqlite.refused_write(err) then
    q.err = nil
    q.notice = "Stopped at a statement that writes; nothing was changed."
    S.redraw()
    ttt.confirm("This query writes to " .. q.db.name .. ". Run it again with write access?", U.bind(M.run, q, true))
    return
  end
  q.ran = true
  q.stopped = stopped
  q.timeout_ms = info.timeout_ms
  if stopped then
    q.err = info.stderr ~= "" and info.stderr or nil
  else
    q.err = err
  end
  q.changes = split_changes(sets)
  q.sets = sets
  q.notes = info.notes or {}
  q.elapsed = info.elapsed
  q.wrote = write
  q.active = math.max(#sets, 1)
  q.offset = 0
  q.grid.sel = 1
  if write then
    Db.changed(q.db)
  end
  S.redraw()
end

local function tick(q)
  if q.running then
    S.redraw()
  else
    stop_ticker(q)
  end
end

-- Running again while a run is in flight replaces it: the old sqlite3 is
-- killed and its result, which still arrives, is dropped by the gen check.
function M.run(q, write)
  if U.trim(q.sql) == "" then
    q.err = "Type some SQL first"
    S.redraw()
    return
  end
  Sqlite.cancel(q.job)
  write = write == true or q.write
  q.gen = q.gen + 1
  q.running = true
  q.started = os.clock()
  q.received = 0
  q.err = nil
  q.notice = nil
  stop_ticker(q)
  q.ticker = ttt.set_interval(500, U.bind(tick, q))
  q.job = Sqlite.run(q.db, script(q.sql), {
    write = write,
    limit = tonumber(S.settings.query_row_limit),
    timeout_ms = S.query_timeout_ms(),
    on_progress = U.bind(received, q, q.gen),
  }, U.bind(finished, q, q.gen, write))
  S.redraw()
end

function M.cancel(q)
  Sqlite.cancel(q.job)
end

-- For a closed tab: nothing is left to show the result in.
function M.dispose(q)
  q.gen = q.gen + 1
  stop_ticker(q)
  Sqlite.cancel(q.job)
  q.job = nil
end

function M.set_sql(q, text)
  q.sql = text
end

function M.set_write(q, checked)
  q.write = checked
end

function M.select_set(q, id)
  q.active = tonumber(id) or 1
  q.offset = 0
  q.grid.sel = 1
  S.redraw()
end

function M.set_page(q, offset)
  q.offset = offset
  S.redraw()
end

return M
