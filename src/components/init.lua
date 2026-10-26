-- The component library as one table, so callers write UI.frame, UI.dialog, …
local UI = {}

for _, name in ipairs({ "layout", "inputs", "form", "dialog", "grid" }) do
  for k, v in pairs(require("components." .. name)) do
    assert(UI[k] == nil, "components: " .. k .. " is defined twice")
    UI[k] = v
  end
end

return UI
