local text = require("ttt.text")
local U = require("core.util")

local M = {}

local function merge(into, opts)
  for k, v in pairs(opts or {}) do
    into[k] = v
  end
  return into
end

local function checkbox_cell(spec, b)
  b:checkbox(spec)
end

local function button_cell(spec, b)
  b:button(spec)
end

function M.frame(p, title, render, opts)
  p:box(merge({ border = true, title = title, render = render }, opts))
end

function M.toolbar(p, render, margin_top)
  p:hstack({ height = 1, gap = 1, margin_top = margin_top == nil and 1 or margin_top, render = render })
end

function M.checkbox(h, label, checked, on_change, opts)
  local spec = { label = label, checked = checked, on_change = on_change }
  h:box(merge({ width = U.width(label) + 5, render = U.bind(checkbox_cell, spec) }, opts))
end

-- A button aligned with bordered inputs in the same row.
function M.button_box(h, label, on_click, disabled, style)
  local spec = { label = label, on_click = on_click, disabled = disabled, style = style }
  local width = U.width(label) + 2 + (style == "bracket" and 2 or 0)
  h:box({ padding_top = 1, width = width, render = U.bind(button_cell, spec) })
end

-- Wraps msg to the panel width after opts.prefix, one label per line. With
-- opts.rows it takes exactly that many rows, ending in "…" when cut short.
function M.message(p, msg, style, opts)
  opts = opts or {}
  local prefix = opts.prefix or ""
  local pad = string.rep(" ", U.width(prefix))
  local width = math.max((p:size()) - 1 - #pad, 1)
  local lines = msg == "" and { "" } or text.wrap(msg, width)
  local rows = opts.rows or #lines
  if #lines > rows then
    lines[rows] = U.clip(lines[rows] .. " …", width)
  end
  for i = 1, rows do
    p:label({
      text = lines[i] and ((i == 1 and prefix or pad) .. lines[i]) or "",
      style = style,
      padding_left = 1,
      margin_top = i == 1 and opts.margin_top or nil,
    })
  end
end

function M.kv(entries)
  local out = { padding_left = 1, margin_top = 1, muted_keys = true }
  for _, e in ipairs(entries) do
    out[#out + 1] = { key = e[1], value = e[2] or "" }
  end
  return out
end

return M
