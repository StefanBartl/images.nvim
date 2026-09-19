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

  -- ── A typo'd nested option is rejected, not swallowed into the default
  --    (ERR-50) ───────────────────────────────────────────────────────────
  cfg = config.setup({ paste = { ask_altext = true } })
  H.eq(cfg.paste.ask_alt_text, false, "the misspelled key never applies -- the real option keeps its default")
  H.falsy(cfg.paste.ask_altext, "…and the typo itself is not merged in as a dead field")
  H.ok(#config.issues() > 0, "the typo is recorded as an issue for :checkhealth")
  H.contains(config.issues()[1], "ask_alt_text", "…naming the option it was probably meant to be")

  -- ── A wrong-shaped nested table is dropped, not merged as-is ─────────────
  cfg = config.setup({ display = "not a table" })
  H.eq(cfg.display.max_cols, 60, "a scalar given where `display` expects a table falls back to the default")
  H.ok(#config.issues() > 0, "…and is recorded as an issue")

  -- ── A clean setup() reports no issues ────────────────────────────────────
  config.setup({ display = { max_cols = 30 } })
  H.eq(#config.issues(), 0, "a recognized option leaves no issues behind")

  config.setup({}) -- neutral again for any spec that runs after this one
end
