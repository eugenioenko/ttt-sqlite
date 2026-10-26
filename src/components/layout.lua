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
  h:box(merge({ width = #label + 5, render = U.bind(checkbox_cell, spec) }, opts))
end

-- A button aligned with bordered inputs in the same row.
function M.button_box(h, label, on_click, disabled, style)
  local spec = { label = label, on_click = on_click, disabled = disabled, style = style }
  local width = #label + 2 + (style == "bracket" and 2 or 0)
  h:box({ padding_top = 1, width = width, render = U.bind(button_cell, spec) })
end

function M.kv(entries)
  local out = { padding_left = 1, margin_top = 1, muted_keys = true }
  for _, e in ipairs(entries) do
    out[#out + 1] = { key = e[1], value = e[2] or "" }
  end
  return out
end

return M
