---@module 'images.config'
---@brief Konfigurations-Einstieg: Defaults mit User-Optionen zusammenführen.

local M = {}

---@type ImagesNvim.Config|nil
local current = nil

---@type table|nil
local user_opts = nil

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

  user_opts = vim.deepcopy(opts or {})
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), calibrated, opts or {})
  return current
end

--- The options this plugin was last set up with, unmerged.
---
--- Only interesting to answer one question: did the user set this themselves?
--- The merged configuration cannot say — a value there may come from the
--- defaults, from a stored calibration, or from the spec, and they are
--- indistinguishable once merged. `:Image calibrate` needs the difference, so
--- it can warn when a hand-written option silently shadows what was just
--- measured; being quietly overridden would be the worst of the three.
---@return table
function M.user_opts()
  return user_opts or {}
end

--- Aktive Konfiguration. Fällt auf die Defaults zurück, falls `setup()` nie
--- gelaufen ist — so bleibt die Lua-API auch ohne Setup benutzbar.
---@return ImagesNvim.Config
function M.get()
  if not current then return M.setup(nil) end
  return current
end

return M
