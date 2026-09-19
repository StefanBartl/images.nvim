---@module 'images.calibration'
---@brief Persist measured placement values across restarts.
---@description
--- `:Image calibrate` produces values that hold for *this* terminal
--- installation — not for the plugin, and not for a project. They therefore
--- belong neither in the repository's configuration nor in a `setup()` spec
--- the user may well sync between machines: the same `terminal_padding` or
--- `cell_aspect` would simply be wrong on another machine with a different
--- font size.
---
--- So `stdpath("data")`, where machine-local state belongs, and deliberately
--- **not** an edit to the user's spec. A plugin that writes into someone
--- else's configuration files unasked is a plugin they stop trusting at the
--- next update — and a merge conflict in a versioned dotfile collection would
--- be poor thanks for a calibration.
---
--- **Precedence.** Defaults < stored calibration < explicit `setup()` options.
--- Whoever writes a value into their own spec is always right: they decided,
--- the calibration merely measured. `:Image calibrate` points it out when such
--- an option shadows the measured value — being silently overridden would be
--- the worst of the three outcomes.

local M = {}

---@internal
---@return string dir
local function dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "images.nvim")
end

--- Path of the calibration file.
---@return string
function M.path()
  return vim.fs.joinpath(dir(), "calibration.json")
end

---@type table|nil
local cached = nil
---@type boolean
local loaded = false
---@type string|nil
local load_err = nil

--- Read the stored values. A missing or empty file is not an error case but
--- the normal state before the first calibration; a file that exists but
--- fails to decode as JSON is corrupt, which — unlike "missing" — is worth
--- surfacing (see `err`, and `:checkhealth images`).
---@param force boolean|nil discard the memoized result
---@return table values empty when nothing is stored, or the file is corrupt
---@return string|nil err set only when the file exists but could not be read
function M.load(force)
  if loaded and not force then return cached or {}, load_err end
  loaded = true
  cached = {}
  load_err = nil

  local f = io.open(M.path(), "r")
  if not f then return cached, nil end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then return cached, nil end

  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then
    cached = decoded
  else
    load_err = "calibration file is corrupt: " .. M.path()
    -- Preserve the unreadable file next to itself rather than silently
    -- discarding it: `M.save` always rewrites the WHOLE file (load-modify-
    -- save), so without this the next `:Image calibrate` would overwrite a
    -- corrupt file with only the newly measured keys, and any earlier
    -- measurement in it would be gone with no one ever having seen it.
    pcall(vim.uv.fs_copyfile, M.path(), M.path() .. ".corrupt")
  end
  return cached, load_err
end

--- Store values. Existing entries are kept, so a partial calibration does not
--- wipe an earlier complete one.
---@param values table
---@return boolean ok
---@return string|nil err
function M.save(values)
  if type(values) ~= "table" then return false, "no values given" end

  local merged = vim.tbl_deep_extend("force", M.load(true), values)

  local made = vim.fn.mkdir(dir(), "p")
  if made == 0 and vim.fn.isdirectory(dir()) == 0 then return false, "cannot create directory: " .. dir() end

  local ok_enc, encoded = pcall(vim.json.encode, merged)
  if not ok_enc then return false, "not serializable: " .. tostring(encoded) end

  local f, ferr = io.open(M.path(), "w")
  if not f then return false, tostring(ferr) end
  f:write(encoded)
  f:close()

  cached, loaded = merged, true
  return true
end

--- Discard the stored values.
---@return boolean ok
function M.clear()
  cached, loaded = {}, true
  local ok = os.remove(M.path())
  return ok ~= nil or vim.fn.filereadable(M.path()) == 0
end

--- The two keys `:Image calibrate` ever writes (see `images.calibrate`'s
--- `offer_save`), with a check for the shape each must have. A persisted file
--- is untrusted input (SEC-33): it is user-editable JSON, not `setup()`
--- Lua, and `config.setup` deep-merges whatever `as_config` returns straight
--- into the live `display` table with no validation of its own.
---@type table<string, fun(v: any): boolean>
local KNOWN = {
  terminal_padding = function(v)
    return type(v) == "table" and type(v.row) == "number" and type(v.col) == "number"
  end,
  cell_aspect = function(v)
    return type(v) == "number"
  end,
}

--- The calibration as a `display` sub-table, shaped the way `config.setup`
--- expects it. Empty when nothing is stored, or when the stored file is
--- corrupt or hand-edited beyond the two keys above — everything then
--- behaves as if this module did not exist, rather than handing an
--- unvalidated table straight into the live configuration.
---@return table
function M.as_config()
  local values = M.load()
  local out = {}
  for key, is_valid in pairs(KNOWN) do
    local v = values[key]
    if v ~= nil and is_valid(v) then out[key] = v end
  end
  if vim.tbl_isempty(out) then return {} end
  return { display = out }
end

return M
