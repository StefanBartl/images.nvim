---@module 'images.config'
---@brief Konfigurations-Einstieg: Defaults mit User-Optionen zusammenführen.

local M = {}

---@type ImagesNvim.Config|nil
local current = nil

--- User-Optionen über die Defaults legen.
---@param opts table|nil
---@return ImagesNvim.Config
function M.setup(opts)
  local defaults = require("images.config.DEFAULTS")
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return current
end

--- Aktive Konfiguration. Fällt auf die Defaults zurück, falls `setup()` nie
--- gelaufen ist — so bleibt die Lua-API auch ohne Setup benutzbar.
---@return ImagesNvim.Config
function M.get()
  if not current then return M.setup(nil) end
  return current
end

return M
