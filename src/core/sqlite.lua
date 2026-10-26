local sys = require("ttt.system")
local U = require("core.util")
local S = require("core.state")
local R = require("core.results")

-- Every call runs one sqlite3 process: `sqlite3 -json <uri>` with the SQL on
-- stdin. Attached databases are attached again each time with -cmd.
local M = {}

local noinit = true

local function attach_args(db, write)
  local args = {}
  for _, a in ipairs(db.attachments or {}) do
    args[#args + 1] = "-cmd"
    args[#args + 1] = "ATTACH " .. U.literal(U.uri(a.path, write)) .. " AS " .. U.ident(a.alias)
  end
  return args
end

function M.build_args(db, opts)
  local args = {}
  if noinit then
    args[#args + 1] = "-noinit"
  end
  args[#args + 1] = "-batch"
  args[#args + 1] = "-json"
  for _, a in ipairs(attach_args(db, opts.write)) do
    args[#args + 1] = a
  end
  -- -bail on the command line makes sqlite3 exit right after the first -cmd
  -- SQL, before reading stdin; turning it on from a -cmd after ATTACH works.
  if opts.bail ~= false then
    args[#args + 1] = "-cmd"
    args[#args + 1] = ".bail on"
  end
  args[#args + 1] = U.uri(db.path, opts.write)
  return args
end

-- A read-only run stops with this error at the first statement that writes,
-- before it changes anything.
function M.refused_write(err)
  return err ~= nil and err:find("attempt to write a readonly database", 1, true) ~= nil
end

local function friendly(err, binary)
  err = U.trim(err)
  binary = binary or S.binary()
  if err:find("executable file not found", 1, true) or err:find("no such file or directory", 1, true) then
    return "sqlite3 not found: " .. binary .. " (see SQLite: Settings…)"
  end
  if err:find("permission denied: system.exec", 1, true) then
    if binary:sub(1, 1) == "/" then
      return binary .. " is not approved: save it in SQLite: Settings… to approve it"
    end
    return "Only sqlite3 on PATH or the absolute path of a sqlite3 binary can run, not " .. binary
  end
  return err
end

local function timeout_ms(opts)
  if opts.timeout_ms == nil then
    return S.CATALOG_TIMEOUT_MS
  end
  return opts.timeout_ms
end

local function on_chunk(parser, opts, chunk)
  R.feed(parser, chunk)
  if opts.on_progress then
    opts.on_progress(parser.sets)
  end
end

local function stopped_err(opts, result)
  if result.cancelled then
    return "Cancelled"
  elseif result.timed_out then
    return "Timed out after " .. U.duration(timeout_ms(opts))
  end
  return "Stopped reading after " .. U.bytes(opts.max_bytes or S.OUTPUT_LIMIT) .. " of output"
end

local start

local function finished(job, db, sql, opts, cb, parser, result)
  local stderr = result.stderr or ""
  if noinit and stderr:find("-noinit", 1, true) and stderr:find("unknown option", 1, true) then
    noinit = false
    return start(job, db, sql, opts, cb)
  end
  job.done = true
  local stopped = result.cancelled or result.timed_out or result.truncated
  local info = {
    elapsed = os.clock() - job.started,
    exit_code = result.exit_code,
    cancelled = result.cancelled,
    timed_out = result.timed_out,
    truncated = result.truncated,
    timeout_ms = timeout_ms(opts),
    stderr = (result.cancelled or result.timed_out) and "" or U.trim(stderr),
  }
  if result.exit_code == -1 and not stopped then
    return cb(friendly(stderr), {}, info)
  end
  local sets, notes = R.finish(parser, not stopped)
  if not sets then
    return cb(notes, {}, info)
  end
  info.notes = notes
  local err = info.stderr
  if stopped then
    err = err ~= "" and err or stopped_err(opts, result)
  elseif err == "" and result.exit_code ~= 0 then
    err = "sqlite3 exited with code " .. tostring(result.exit_code)
  end
  cb(err ~= "" and err or nil, sets, info)
end

start = function(job, db, sql, opts, cb)
  local parser = R.stream(opts.limit)
  local exec_opts = {
    stdin = sql .. "\n",
    max_output_bytes = opts.max_bytes or S.OUTPUT_LIMIT,
    on_stdout = U.bind(on_chunk, parser, opts),
  }
  local ms = timeout_ms(opts)
  if ms > 0 then
    exec_opts.timeout_ms = ms
  end
  job.started = os.clock()
  local handle, err =
    sys.exec_async(S.binary(), M.build_args(db, opts), exec_opts, U.bind(finished, job, db, sql, opts, cb, parser))
  if err then
    job.done = true
    return cb(friendly(err), {}, {})
  end
  job.handle = handle
end

-- cb(err, sets, info): err is sqlite3's stderr when it printed anything, or
-- why it stopped; the sets that arrived before are still passed. info has
-- elapsed, notes, stderr, and cancelled, timed_out or truncated (the output
-- passed max_bytes) when sqlite3 was stopped. opts: write (open read-write),
-- bail (stop at the first error, default true), limit (rows kept per set),
-- timeout_ms (0 for none, default the catalog timeout), max_bytes,
-- on_progress(sets). Returns a job for M.cancel.
function M.run(db, sql, opts, cb)
  opts = opts or {}
  local job = { done = false }
  if not sys.exec_async then
    job.done = true
    cb("This plugin needs the system.exec permission to run sqlite3", {}, {})
    return job
  end
  start(job, db, sql, opts, cb)
  return job
end

function M.cancel(job)
  if not job or job.done or not job.handle then
    return false
  end
  return job.handle:cancel()
end

local function version_done(binary, cb, result)
  local out = U.trim(result.stdout)
  if result.timed_out then
    return cb(binary .. " -version did not answer in " .. U.duration(S.VERSION_TIMEOUT_MS))
  end
  if result.exit_code ~= 0 or out == "" then
    return cb(friendly(result.stderr ~= "" and result.stderr or "sqlite3 -version failed", binary))
  end
  cb(nil, out:match("^(%S+)") or out)
end

-- cb(err, version, denied): denied when ttt has not approved running binary.
function M.version(binary, cb)
  if not sys.exec_async then
    return cb("This plugin needs the system.exec permission to run sqlite3")
  end
  local _, err = sys.exec_async(
    binary,
    { "-version" },
    { timeout_ms = S.VERSION_TIMEOUT_MS },
    U.bind(version_done, binary, cb)
  )
  if err then
    cb(friendly(err, binary), nil, err:find("permission denied", 1, true) ~= nil)
  end
end

return M
