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

local function build_args(db, opts)
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

local function friendly(err)
  err = U.trim(err)
  if err:find("executable file not found", 1, true) or err:find("no such file or directory", 1, true) then
    return "sqlite3 not found: " .. S.binary() .. " (see SQLite: Settings…)"
  end
  if err:find("permission denied: system.exec", 1, true) then
    return "Not in system.exec in plugin.ttt.json: " .. S.binary()
  end
  return err
end

local function finished(db, sql, opts, cb, started, result)
  local stderr = result.stderr or ""
  if noinit and stderr:find("-noinit", 1, true) and stderr:find("unknown option", 1, true) then
    noinit = false
    return M.run(db, sql, opts, cb)
  end
  local elapsed = os.clock() - started
  if result.exit_code == -1 then
    return cb(friendly(stderr), {}, { elapsed = elapsed })
  end
  local sets, notes = R.parse(result.stdout, opts.limit)
  if not sets then
    return cb(notes, {}, { elapsed = elapsed })
  end
  local err = U.trim(stderr)
  if err == "" and result.exit_code ~= 0 then
    err = "sqlite3 exited with code " .. tostring(result.exit_code)
  end
  cb(err ~= "" and err or nil, sets, { elapsed = elapsed, notes = notes, exit_code = result.exit_code })
end

-- cb(err, sets, info): err is sqlite3's stderr when it printed anything; the
-- sets that ran before an error are still passed. opts: write (open
-- read-write), bail (stop at the first error, default true), limit (rows kept
-- per set).
function M.run(db, sql, opts, cb)
  opts = opts or {}
  if not sys.exec_async then
    return cb("This plugin needs the system.exec permission to run sqlite3", {}, {})
  end
  local started = os.clock()
  local _, err = sys.exec_async(
    S.binary(),
    build_args(db, opts),
    { stdin = sql .. "\n" },
    U.bind(finished, db, sql, opts, cb, started)
  )
  if err then
    cb(friendly(err), {}, {})
  end
end

local function version_done(cb, result)
  local out = U.trim(result.stdout)
  if result.exit_code ~= 0 or out == "" then
    return cb(friendly(result.stderr ~= "" and result.stderr or "sqlite3 -version failed"))
  end
  cb(nil, out:match("^(%S+)") or out)
end

function M.version(cb)
  if not sys.exec_async then
    return cb("This plugin needs the system.exec permission to run sqlite3")
  end
  local _, err = sys.exec_async(S.binary(), { "-version" }, U.bind(version_done, cb))
  if err then
    cb(friendly(err))
  end
end

return M
