local U = require("core.util")
local S = require("core.state")
local Layout = require("components.layout")
local Inputs = require("components.inputs")

-- Forms from a field spec: { key, label, kind = "enum"|"multiline"|"readonly",
-- options, value, placeholder, password, required, rows, show(vals) }, and
-- spec { fields, submit, busy_text, on_submit(vals, done), on_done }.
local M = {}

function M.field_options(f)
  if type(f.options) == "function" then
    return f.options()
  end
  return f.options or {}
end

local function shown(form, f)
  return not f.show or f.show(form.vals)
end

local function finish(form, err)
  form.busy = false
  form.err = err
  if not err and form.spec.on_done then
    form.spec.on_done()
  end
  S.redraw()
end

local function submit(form)
  if form.busy then
    return
  end
  for _, f in ipairs(form.spec.fields) do
    if shown(form, f) and f.required and U.trim(form.vals[f.key]) == "" then
      form.err = f.label .. " is required"
      S.redraw()
      return
    end
  end
  form.busy = true
  form.err = nil
  S.redraw()
  form.spec.on_submit(form.vals, U.bind(finish, form))
end

function M.new_form(spec)
  local form = { spec = spec, vals = {}, err = nil, busy = false }
  for _, f in ipairs(spec.fields) do
    local v = f.value
    if v == nil and f.options then
      local options = M.field_options(f)
      if options[1] then
        v = options[1].value
      end
    end
    form.vals[f.key] = v or ""
  end
  form.submit = U.bind(submit, form)
  return form
end

function M.form_height(form)
  local h = 3
  for _, f in ipairs(form.spec.fields) do
    if shown(form, f) then
      if f.kind == "multiline" then
        h = h + (f.rows or 6) + 2
      else
        h = h + 3
      end
    end
  end
  return h
end

local function set_value(form, key, value)
  form.vals[key] = value
end

local function pick_value(form, key, value)
  form.vals[key] = value
  S.redraw()
end

local function enum_field(form, f, b)
  Inputs.dropdown(b, M.field_options(f), form.vals[f.key], U.bind(pick_value, form, f.key))
end

local function render_field(p, form, f, first)
  if f.kind == "enum" then
    Layout.frame(p, f.label, U.bind(enum_field, form, f))
  elseif f.kind == "readonly" then
    p:label({ text = f.label .. ": " .. tostring(form.vals[f.key]), style = "muted", border = true })
  else
    local rows = f.kind == "multiline" and (f.rows or 6) or nil
    p:input({
      border = true,
      title = f.label,
      value = form.vals[f.key],
      placeholder = f.placeholder,
      password = f.password,
      multiline = rows ~= nil,
      min_rows = rows,
      max_rows = rows,
      autofocus = first,
      on_change = U.bind(set_value, form, f.key),
      on_submit = form.submit,
    })
  end
end

local function buttons(form, on_cancel, h)
  h:button({ label = "Cancel", style = "muted", on_click = on_cancel })
  h:button({ label = form.spec.submit or "Save", style = "bracket", disabled = form.busy, on_click = form.submit })
end

function M.render_form(p, form, on_cancel)
  for i, f in ipairs(form.spec.fields) do
    if shown(form, f) then
      render_field(p, form, f, i == 1)
    end
  end
  if form.err then
    Layout.message(p, U.one_line(form.err), "danger", { rows = 2, prefix = "✕ " })
  else
    Layout.message(p, form.busy and (form.spec.busy_text or "Saving…") or "", "muted", { rows = 2 })
  end
  p:hstack({ height = 1, gap = 1, align = "right", render = U.bind(buttons, form, on_cancel) })
end

return M
