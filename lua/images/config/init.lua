---@module 'images.config'
---@brief Configuration entry point: merge user options over the defaults.

local M = {}

---@type ImagesNvim.Config|nil
local current = nil

---@type table|nil
local user_opts = nil

--- Layer user options over the defaults.
---
--- The stored calibration sits in between (`:Image calibrate`, see
--- `images.calibration`): defaults < calibration < explicit options. Writing a
--- value into your own `setup()` spec therefore outranks the measurement — by
--- design, a decision weighs more than a measurement. `pcall`, because an
--- unreadable state file must never make `setup()` fail.
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

--- The active configuration. Falls back to the defaults if `setup()` never
--- ran, so the Lua API stays usable without setup.
---@return ImagesNvim.Config
function M.get()
  if not current then return M.setup(nil) end
  return current
end

return M
