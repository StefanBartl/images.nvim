---@module 'images.config'
---@brief Configuration entry point: merge user options over the defaults.

local M = {}

---@type ImagesNvim.Config|nil
local current = nil

---@type table|nil
local user_opts = nil

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- The shape `setup()` recognizes, mirroring `config.DEFAULTS` one level of
--- nesting at a time: `true` accepts any value at that leaf (several are
--- polymorphic — a keymap is a string or `false`, `ocr.args`/`extensions` are
--- lists), a nested table validates its own keys the same way, recursively.
---@alias ImagesNvim.Config.Schema true|table<string, ImagesNvim.Config.Schema>
---@type table<string, ImagesNvim.Config.Schema>
local KNOWN = {
  command = true,
  extensions = true,
  display = {
    max_cols = true,
    max_rows = true,
    cell_aspect = true,
    draw_inset = true,
    terminal_padding = { row = true, col = true },
    gallery_gap = true,
    hover_mode = true,
    assume_supported = true,
    clear_events = true,
    browse_exclude = true,
    browse_max_entries = true,
    zen = { width = true, height = true },
    remote = { enabled = true, timeout_ms = true, max_bytes = true, cache_ttl_s = true },
    screenshot = { windows_timeout_ms = true, windows_poll_interval_ms = true },
    redact = { padding_cells = true },
    ascii_fallback = { enabled = true, levels = true, cells = true },
    gopath_fallback = true,
  },
  paste = {
    dir = true,
    existing_dir_names = true,
    name_template = true,
    link_template = true,
    ask_alt_text = true,
    alt_link_template = true,
    ask_filename = true,
  },
  ocr = { lang = true, args = true, bin = true },
  deps_popup = true,
  pdf = { enabled = true, page = true, dpi = true },
  menu = { enable = true },
  keymaps = {
    show = true,
    gallery = true,
    next = true,
    prev = true,
    paste = true,
    screenshot = true,
    double_click = true,
    filetypes = true,
  },
}

--- `key` with the nearest sibling in `known` as a hint, when there is a
--- plausible one (edit distance <= 3) — catches the everyday typo
--- (`ask_altext` for `ask_alt_text`) without claiming a match for a key that
--- is not actually related.
---@internal
---@param key any
---@param known table<string, any>
---@param prefix string dotted path so far, e.g. "display."
---@return string
local function describe_unknown(key, known, prefix)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best) end
  return ("unknown option '%s%s'"):format(prefix, name)
end

--- Validate `opts` against `KNOWN` before the merge (ERR-50): an
--- unrecognized key — almost always a typo in a nested option — would
--- otherwise vanish silently into the default, with the plugin behaving as
--- if it had never been set at all. Recurses into a nested table the same
--- way; a value given where a nested table is expected is dropped too, so a
--- wrong shape falls back to the default rather than reaching
--- `vim.tbl_deep_extend` as-is.
---
--- Does not mutate `opts` — a rejected entry is left out of the returned
--- copy rather than stripped from the caller's own table; an accepted leaf
--- is deep-copied so the returned table shares no reference with the
--- caller's (ERR-51).
---@internal
---@param opts table
---@param schema table<string, ImagesNvim.Config.Schema>
---@param prefix string
---@return table clean
---@return string[] found_issues
local function sanitize(opts, schema, prefix)
  local clean, found_issues = {}, {}
  for key, value in pairs(opts) do
    local expected = schema[key]
    if expected == nil then
      found_issues[#found_issues + 1] = describe_unknown(key, schema, prefix)
    elseif expected == true then
      clean[key] = vim.deepcopy(value)
    elseif type(value) ~= "table" then
      found_issues[#found_issues + 1] = ("option '%s%s' must be a table, got %s — using the default"):format(
        prefix,
        tostring(key),
        type(value)
      )
    else
      local sub_clean, sub_issues = sanitize(value, expected, prefix .. tostring(key) .. ".")
      clean[key] = sub_clean
      vim.list_extend(found_issues, sub_issues)
    end
  end
  return clean, found_issues
end

---@type string[]
local issues = {}

--- Whatever the last `setup()` had to reject — for `:checkhealth images`.
---@return string[]
function M.issues()
  return issues
end

--- Layer user options over the defaults.
---
--- The stored calibration sits in between (`:Image calibrate`, see
--- `images.calibration`): defaults < calibration < explicit options. Writing a
--- value into your own `setup()` spec therefore outranks the measurement — by
--- design, a decision weighs more than a measurement. `pcall`, because an
--- unreadable state file must never make `setup()` fail.
---
--- `opts` is validated first (ERR-50): an unknown key or a wrong-shaped
--- value is dropped so the built-in default is what actually takes effect,
--- and every issue is both warned here (once) and kept for `:checkhealth`
--- (see `M.issues()`).
---@param opts ImagesNvim.Opts|nil
---@return ImagesNvim.Config
function M.setup(opts)
  local defaults = require("images.config.DEFAULTS")

  local calibrated = {}
  local ok, values = pcall(function()
    return require("images.calibration").as_config()
  end)
  if ok and type(values) == "table" then calibrated = values end

  local clean, found_issues = sanitize(opts or {}, KNOWN, "")
  table.sort(found_issues)
  issues = found_issues
  if #found_issues > 0 then notify().warn("setup(): " .. table.concat(found_issues, "; ")) end

  user_opts = clean
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), calibrated, clean)
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
