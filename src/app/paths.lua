local sys = require("ttt.system")
local U = require("core.util")

local M = {}

local function env(name)
  if not sys.env then
    return ""
  end
  return sys.env(name) or ""
end

-- Absolute path for what the user typed: ~ is the home directory, and a
-- relative path is taken from the directory ttt started in.
function M.normalize(text)
  local path = U.trim(text)
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  path = path:gsub("^file://", "")
  if path == "" then
    return ""
  end
  if path == "~" or path:sub(1, 2) == "~/" then
    local home = env("HOME")
    if home ~= "" then
      path = home .. path:sub(2)
    end
  elseif path:sub(1, 1) ~= "/" then
    local cwd = env("PWD")
    if cwd ~= "" then
      path = cwd:gsub("/+$", "") .. "/" .. path
    end
  end
  path = path:gsub("/%./", "/"):gsub("/+", "/")
  return path
end

function M.display(path)
  local home = env("HOME")
  if home ~= "" and path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

return M
