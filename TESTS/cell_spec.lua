-- TESTS/cell_spec.lua — images.cell: the effective terminal-cell aspect
-- ratio, where it comes from, and where apply() writes it.
--
-- Pure configuration arithmetic, no terminal involved -- unlike
-- images.calibrate, which nudges this interactively and stays untested (see
-- calibration_spec.lua's header).
--
-- Must run before anything that calls `images.cell.default()`/`.apply()` for
-- the first time in this process: `assumed` is cached from
-- `images.scale.CELL_ASPECT` on its first call only (see the module's own
-- docs on why), so a spec that got there first would decide what "the
-- assumption" means for every spec after it. blocks_spec.lua's
-- `require("images").setup({})` is the one other caller in this suite (via
-- `images.init.M.setup`), and it runs last -- see TESTS/run.lua's specs list.

---@param H table harness from TESTS/run.lua
return function(H)
  local cell = require("images.cell")
  local scale = require("images.scale")
  local config = require("images.config")

  local real_cell_aspect = scale.CELL_ASPECT

  config.setup({})

  -- ── default(): the built-in assumption, whatever it is ───────────────────
  local default = cell.default()
  H.ok(type(default) == "number" and default > 0, "default() is a positive number")
  H.eq(cell.default(), default, "default() is stable across calls")

  -- ── aspect(): unset configuration falls back to the assumption ───────────
  -- 0 is "unset" (see config/DEFAULTS.lua's own comment on cell_aspect), not
  -- a real ratio -- a wrong reading here would flatten every image to a line.
  config.setup({ display = { cell_aspect = 0 } })
  H.eq(cell.aspect(), default, "aspect() falls back to the assumption when cell_aspect = 0")

  -- ── aspect(): a configured value wins over the assumption ────────────────
  config.setup({ display = { cell_aspect = 0.46 } })
  H.eq(cell.aspect(), 0.46, "aspect() prefers a configured value")

  -- ── aspect(): an invalid configured value degrades, it does not propagate ─
  config.setup({ display = { cell_aspect = -1 } })
  H.eq(cell.aspect(), default, "a negative configured value falls back rather than producing a negative aspect")

  -- ── apply(): writes the effective ratio into images.scale.CELL_ASPECT ────
  config.setup({ display = { cell_aspect = 0.6123 } })
  local applied = cell.apply()
  H.eq(applied, 0.6123, "apply() returns the effective ratio")
  H.eq(scale.CELL_ASPECT, 0.6123, "…and writes it where every fit_cells caller reads it")

  -- ── default() is unaffected by apply()/configuration ─────────────────────
  H.eq(cell.default(), default, "default() stays the built-in assumption regardless of apply() or configuration")

  -- Clean up: real config, real CELL_ASPECT — later specs (anchor_spec.lua)
  -- already defensively pin CELL_ASPECT themselves, but there is no reason to
  -- leave this test's value standing for whoever runs between here and there.
  config.setup({})
  scale.CELL_ASPECT = real_cell_aspect
end
