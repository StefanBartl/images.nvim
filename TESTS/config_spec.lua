-- TESTS/config_spec.lua — defaults, merging, usability without setup().

---@param H table harness from TESTS/run.lua
return function(H)
  local config = require("images.config")

  -- ── Defaults ───────────────────────────────────────────────────────────────
  local cfg = config.setup(nil)
  H.eq(cfg.command, "Image", "default command")
  H.eq(cfg.display.max_cols, 60, "default width in cells")
  H.eq(cfg.display.redact.padding_cells, 1, "default safety margin for :Image redact")
  H.eq(cfg.paste.dir, "assets", "default target directory")
  H.eq(#cfg.paste.existing_dir_names, 2, "default: two recognised resource folder names")
  H.eq(cfg.paste.existing_dir_names[1], "Resources", "…the English name first")
  H.ok(#cfg.extensions > 0, "there are default extensions")

  -- ── A partial override leaves the rest standing ──────────────────────────
  cfg = config.setup({ display = { max_cols = 30 } })
  H.eq(cfg.display.max_cols, 30, "the value that was set wins")
  H.eq(cfg.display.max_rows, 25, "an unset neighbour keeps its default")
  H.eq(cfg.command, "Image", "other sections stay untouched")

  -- ── Keymaps can be disabled individually ─────────────────────────────────
  cfg = config.setup({ keymaps = { show = false } })
  H.eq(cfg.keymaps.show, false, "false disables a single binding")
  H.eq(cfg.keymaps.gallery, "<leader>ig", "the others stay in place")

  -- ── The defaults are never mutated ───────────────────────────────────────
  -- `setup` works on a copy; otherwise a second `setup` would build on the
  -- leftovers of the first rather than on the defaults.
  config.setup({ display = { max_cols = 1 } })
  cfg = config.setup(nil)
  H.eq(cfg.display.max_cols, 60, "a second setup starts from the defaults again")

  -- ── get() works without a prior setup() ──────────────────────────────────
  -- The Lua API should stay usable when the user only sets `opts = {}` through
  -- lazy and never calls `setup` themselves.
  H.ok(config.get() ~= nil, "get() always returns a configuration")
  H.eq(config.get().command, "Image", "…and a complete one at that")
end
