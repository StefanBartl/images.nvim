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
  local f = io.open(sandbox, "w")
  f:write("{ this is not json")
  f:close()
  calibration.load(true)

  local ok_setup, conf2 = pcall(config.setup, {})
  H.ok(ok_setup, "setup() survives an unreadable state file")
  H.eq(
    ok_setup and conf2.display.max_cols,
    require("images.config.DEFAULTS").display.max_cols,
    "…and still returns the defaults"
  )

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
