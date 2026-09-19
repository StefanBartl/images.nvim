-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- And `calibration.path` is replaced below so no run touches the developer's
-- real state file -- a deliberate second definition of the module's own field.
---@diagnostic disable: duplicate-set-field
-- TESTS/calibration_spec.lua — stored calibration values and their precedence.
--
-- The interactive part (`images.calibrate`) is a dialog and stays untested
-- here. What is testable — and more important — is what happens afterwards:
-- that a measured value survives a restart, that an explicit setup() option
-- still outranks it, and that a corrupt state file does not take setup() down
-- with it.

---@param H table harness from TESTS/run.lua
return function(H)
  local calibration = require("images.calibration")
  local config = require("images.config")

  -- A test run must not touch the user's real state file.
  local real_path = calibration.path
  local sandbox = vim.fn.tempname() .. "-calibration.json"
  calibration.path = function()
    return sandbox
  end

  local function reset()
    pcall(os.remove, sandbox)
    calibration.load(true)
  end

  reset()

  -- ── No file: empty, and everything behaves as without this module ────────
  H.eq(vim.tbl_count(calibration.load(true)), 0, "no file means no stored values")
  H.eq(vim.tbl_count(calibration.as_config()), 0, "…and as_config contributes nothing to merge")

  -- ── Save and read back ────────────────────────────────────────────────────
  local ok, err = calibration.save({ terminal_padding = { row = -2, col = 1 } })
  H.ok(ok, "save reports success" .. (err and (" (" .. tostring(err) .. ")") or ""))

  local loaded = calibration.load(true)
  H.eq(loaded.terminal_padding and loaded.terminal_padding.row, -2, "row survives the round trip")
  H.eq(loaded.terminal_padding and loaded.terminal_padding.col, 1, "col survives the round trip")

  local as_cfg = calibration.as_config()
  H.eq(as_cfg.display and as_cfg.display.terminal_padding.row, -2, "as_config nests the values under `display`")

  -- ── Saving merges rather than discarding ─────────────────────────────────
  -- A partial calibration (cell_aspect only) must not wipe an earlier
  -- complete one.
  H.ok(calibration.save({ cell_aspect = 0.46 }), "second save reports success")
  loaded = calibration.load(true)
  H.eq(loaded.cell_aspect, 0.46, "the new value is there")
  H.eq(loaded.terminal_padding and loaded.terminal_padding.row, -2, "…and the old one still stands")

  -- ── Zero is a value, not an absence ──────────────────────────────────────
  -- A correction back to zero has to overwrite a stored non-zero, or a stale
  -- offset can never be undone. The tool once refused to record it at all,
  -- treating "the value is zero" as "nothing was measured"; this pins the
  -- persistence half of that.
  H.ok(calibration.save({ terminal_padding = { row = 0, col = 0 } }), "saving zeros reports success")
  loaded = calibration.load(true)
  H.eq(loaded.terminal_padding.row, 0, "a stored row is overwritten by zero")
  H.eq(loaded.terminal_padding.col, 0, "…and so is a stored col")
  H.eq(loaded.cell_aspect, 0.46, "…while untouched keys survive")
  H.eq(config.setup({}).display.terminal_padding.row, 0, "…and the zero reaches the merged configuration")

  calibration.save({ terminal_padding = { row = -2, col = 1 } }) -- restore for the checks below

  -- ── Precedence: defaults < calibration < explicit options ────────────────
  local conf = config.setup({})
  H.eq(conf.display.terminal_padding.row, -2, "without an option of your own, the measured value applies")
  H.eq(conf.display.cell_aspect, 0.46, "…for every stored key")

  conf = config.setup({ display = { terminal_padding = { row = 5 } } })
  H.eq(conf.display.terminal_padding.row, 5, "an explicit setup() option outranks the measurement")
  H.eq(conf.display.terminal_padding.col, 1, "…without dragging the unset keys along")

  -- Defaults survive for anything neither measured nor set.
  H.eq(conf.display.max_cols, require("images.config.DEFAULTS").display.max_cols, "untouched defaults survive")

  -- ── A corrupt file must not take setup() down ────────────────────────────
  pcall(os.remove, sandbox .. ".corrupt")
  local f = io.open(sandbox, "w")
  f:write("{ this is not json")
  f:close()
  local _, load_err = calibration.load(true)
  H.contains(load_err or "", "corrupt", "corrupt (unlike missing) is reported, not collapsed into empty (ERR-11)")
  H.eq(vim.fn.filereadable(sandbox .. ".corrupt"), 1, "…and the unreadable file is preserved before anything overwrites it")

  local ok_setup, conf2 = pcall(config.setup, {})
  H.ok(ok_setup, "setup() survives an unreadable state file")
  H.eq(
    ok_setup and conf2.display.max_cols,
    require("images.config.DEFAULTS").display.max_cols,
    "…and still returns the defaults"
  )
  pcall(os.remove, sandbox .. ".corrupt")

  -- ── as_config only carries the two keys calibration ever writes, typed
  --    correctly -- a hand-edited or foreign file must not become an
  --    unrestricted overlay on `display` (SEC-33) ───────────────────────────
  do
    local f2 = assert(io.open(sandbox, "w"))
    f2:write(vim.json.encode({
      terminal_padding = { row = 3, col = -1 }, -- valid
      cell_aspect = "wide", -- wrong type -- must be dropped
      remote = { enabled = true }, -- unknown key entirely -- must be dropped
      clear_events = "not a list", -- unknown key -- must be dropped
    }))
    f2:close()
    calibration.load(true)

    local sanitized = calibration.as_config()
    H.eq(sanitized.display.terminal_padding.row, 3, "the correctly-typed known key survives")
    H.falsy(sanitized.display.cell_aspect, "a wrong-typed known key is dropped, not passed through")
    H.falsy(sanitized.display.remote, "an unknown key never reaches the `display` overlay")
    H.falsy(sanitized.display.clear_events, "…not even one that shares a name with a real display option")

    local conf3 = config.setup({})
    H.falsy(conf3.display.remote.enabled, "the default stands: a stray file cannot flip remote.enabled on")
  end

  -- ── clear ─────────────────────────────────────────────────────────────────
  calibration.save({ terminal_padding = { row = -3 } })
  calibration.clear()
  H.eq(vim.tbl_count(calibration.load(true)), 0, "clear removes the stored values")

  -- Clean up: sandbox gone, real path function back, configuration neutral.
  pcall(os.remove, sandbox)
  calibration.path = real_path
  calibration.load(true)
  config.setup({})
end
