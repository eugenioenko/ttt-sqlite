local ttt = require("ttt")
local U = require("core.util")
local S = require("core.state")
local Form = require("components.form")

local M = {}

local function render_dialog(render, p)
  S.panels.dialog = p
  render(p)
end

local function forget_dialog()
  S.panels.dialog = nil
end

function M.open_dialog(title, width, height, render)
  return ttt.open_dialog({
    title = title,
    width = width,
    height = height,
    render = U.bind(render_dialog, render),
    on_close = forget_dialog,
  })
end

local function form_body(form, p)
  Form.render_form(p, form, ttt.close_dialog)
end

function M.dialog(spec)
  local form = Form.new_form(spec)
  spec.on_done = ttt.close_dialog
  return M.open_dialog(spec.title, spec.width or 64, Form.form_height(form), U.bind(form_body, form))
end

return M
