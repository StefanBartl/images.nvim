---@module 'images.config'
---@brief Konfigurations-Einstieg: Defaults mit User-Optionen zusammenführen.

local M = {}

---@type ImagesNvim.Config|nil
local current = nil

--- User-Optionen über die Defaults legen.
---
--- Dazwischen liegt die gespeicherte Kalibrierung (`:Image calibrate`, siehe
--- `images.calibration`): Defaults < Kalibrierung < explizite Optionen. Wer
--- einen Wert selbst in seine `setup()`-Spec schreibt, überstimmt damit die
--- Messung — das ist Absicht, eine Entscheidung wiegt schwerer als ein
--- Messwert. `pcall`, weil eine unlesbare Zustandsdatei niemals `setup()`
--- scheitern lassen darf.
---@param opts table|nil
---@return ImagesNvim.Config
function M.setup(opts)
  local defaults = require("images.config.DEFAULTS")

  local calibrated = {}
  local ok, values = pcall(function()
    return require("images.calibration").as_config()
  end)
  if ok and type(values) == "table" then calibrated = values end

  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), calibrated, opts or {})
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
