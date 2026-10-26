local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Db = require("core.db")
local Sqlite = require("core.sqlite")
local UI = require("components")
local Paths = require("app.paths")
local Router = require("app.router")

-- The Open Database dialog: a path, or one of the recent files.
local M = {}

local form = { path = "", err = nil, busy = false }

local function opened(path, done, err)
  if err then
    return done(err)
  end
  done()
  Db.open(path)
  ttt.show_panel("sidebar")
  if not Router.focus_file(path) then
    ttt.open_file(path)
  end
end

local function checked(path, done, err)
  if err then
    if err:find("unable to open database", 1, true) then
      err = "Cannot open " .. U.basename(path) .. ": not found or not readable"
    elseif err:find("not a database", 1, true) then
      err = U.basename(path) .. " is not an SQLite database"
    end
  end
  opened(path, done, err)
end

-- Opens the file with sqlite3 first, so a wrong path fails here rather than
-- in the sidebar.
function M.open_path(text, done)
  local path = Paths.normalize(text)
  if path == "" then
    return done("Type the path of a database file")
  end
  local probe = { path = path, attachments = {} }
  Sqlite.run(probe, "SELECT count(*) AS n FROM sqlite_master;", {}, U.bind(checked, path, done))
end

local function finish(err)
  form.busy = false
  form.err = err
  if not err then
    ttt.close_dialog()
  end
  S.redraw()
end

local function submit()
  if form.busy then
    return
  end
  form.busy = true
  form.err = nil
  S.redraw()
  M.open_path(form.path, finish)
end

local function set_path(text)
  form.path = text
end

local function open_recent(command, node)
  if command == "activate" and node and node.id then
    form.path = node.id
    submit()
  elseif command == "forget" and node and node.id then
    S.forget(node.id)
    S.redraw()
  end
end

local function recent_items()
  local items = {}
  for i, path in ipairs(S.recent) do
    items[i] = { id = path, label = Paths.display(path) }
  end
  return items
end

local function recent_list(items, b)
  b:list({
    items = items,
    inset = 1,
    truncate_left = true,
    key_commands = { d = "forget" },
    node_menu = { { label = "Open", command = "activate" }, { label = "Remove from Recent", command = "forget" } },
    on_command = open_recent,
  })
end

local function buttons(h)
  h:button({ label = "Cancel", style = "muted", on_click = ttt.close_dialog })
  h:button({ label = form.busy and "Opening…" or "Open", style = "bracket", disabled = form.busy, on_click = submit })
end

local function render(p)
  p:input({
    border = true,
    title = "Database file",
    value = form.path,
    placeholder = "~/data/app.db",
    autofocus = true,
    on_change = set_path,
    on_submit = submit,
  })
  local items = recent_items()
  if #items > 0 then
    p:label({ text = "Recent", style = "muted", padding_left = 1, margin_top = 1 })
    p:box({ height = math.min(#items, 8), render = U.bind(recent_list, items) })
  end
  if form.err then
    UI.message(p, U.one_line(form.err), "danger", { rows = 2, prefix = "✕ " })
  else
    UI.message(p, form.busy and "Opening…" or "", "muted", { rows = 2 })
  end
  p:hstack({ height = 1, gap = 1, align = "right", render = buttons })
end

function M.dialog()
  form.err = nil
  form.busy = false
  local height = 3 + 2 + 1
  if #S.recent > 0 then
    height = height + 2 + math.min(#S.recent, 8)
  end
  UI.open_dialog("Open SQLite Database", 76, height, render)
end

return M
