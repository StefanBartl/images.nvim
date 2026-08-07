-- TESTS/config_spec.lua — Defaults, Zusammenführung, Nutzbarkeit ohne setup().

---@param H table Harness aus TESTS/run.lua
return function(H)
  local config = require("images.config")

  -- ── Defaults ───────────────────────────────────────────────────────────────
  local cfg = config.setup(nil)
  H.eq(cfg.command, "Image", "Default-Command")
  H.eq(cfg.display.max_cols, 60, "Default-Breite in Zellen")
  H.eq(cfg.display.redact.padding_cells, 1, "Default-Sicherheitsmarge für :Image redact")
  H.eq(cfg.paste.dir, "assets", "Default-Zielverzeichnis")
  H.eq(#cfg.paste.existing_dir_names, 2, "Default: zwei erkannte Ressourcen-Ordnernamen")
  H.eq(cfg.paste.existing_dir_names[1], "Resources", "…zuerst der englische Name")
  H.ok(#cfg.extensions > 0, "es gibt Default-Endungen")

  -- ── Teilweise Überschreibung lässt den Rest stehen ─────────────────────────
  cfg = config.setup({ display = { max_cols = 30 } })
  H.eq(cfg.display.max_cols, 30, "gesetzter Wert gewinnt")
  H.eq(cfg.display.max_rows, 25, "nicht gesetzter Nachbar bleibt Default")
  H.eq(cfg.command, "Image", "andere Abschnitte bleiben unberührt")

  -- ── Keymaps lassen sich einzeln abschalten ─────────────────────────────────
  cfg = config.setup({ keymaps = { show = false } })
  H.eq(cfg.keymaps.show, false, "false schaltet eine einzelne Bindung ab")
  H.eq(cfg.keymaps.gallery, "<leader>ig", "die anderen bleiben bestehen")

  -- ── Defaults werden nicht mutiert ──────────────────────────────────────────
  -- `setup` arbeitet auf einer Kopie; sonst würde ein zweites `setup` auf den
  -- Resten des ersten aufsetzen statt auf den Defaults.
  config.setup({ display = { max_cols = 1 } })
  cfg = config.setup(nil)
  H.eq(cfg.display.max_cols, 60, "ein zweites setup startet wieder bei den Defaults")

  -- ── get() funktioniert ohne vorheriges setup() ─────────────────────────────
  -- Die Lua-API soll auch dann benutzbar sein, wenn der User nur `opts = {}`
  -- über lazy setzt und `setup` nie selbst aufruft.
  H.ok(config.get() ~= nil, "get() liefert immer eine Konfiguration")
  H.eq(config.get().command, "Image", "…und zwar eine vollständige")
end
