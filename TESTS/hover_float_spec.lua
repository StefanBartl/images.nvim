-- TESTS/hover_float_spec.lua — Fenstergrößen-Berechnung für den Hover-Float.
--
-- Dieselbe Zurückhaltung wie zen_spec.lua: `M.dimensions` ist reine
-- Mathematik über `vim.o.columns`/`vim.o.lines`, ohne ein Fenster zu öffnen
-- — testbar. Das Zeichnen selbst (`images.terminal.draw`, ausgelöst durch
-- ein echtes `M.open()`) bleibt ungeprüft, wie überall in dieser Suite.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local hover_float = require("images.hover_float")

  -- ── Innerhalb der Editorgröße: max_cols/max_rows gewinnen unverändert ──────
  ---@diagnostic disable-next-line: missing-fields
  local w, h = hover_float.dimensions({ max_cols = 40, max_rows = 15 })
  H.eq(w, 40, "Breite unterhalb der Editorgröße bleibt unverändert")
  H.eq(h, 15, "Höhe unterhalb der Editorgröße bleibt unverändert")

  -- ── Größer als der Editor: auf Editorgröße minus Rand gedeckelt ────────────
  ---@diagnostic disable-next-line: missing-fields
  w, h = hover_float.dimensions({ max_cols = vim.o.columns * 10, max_rows = vim.o.lines * 10 })
  H.eq(w, math.max(1, vim.o.columns - 4), "Breite wird auf die Editorbreite gedeckelt")
  H.eq(h, math.max(1, vim.o.lines - 4), "Höhe wird auf die Editorhöhe gedeckelt")

  -- ── Nie kleiner als 1 Zelle ─────────────────────────────────────────────────
  ---@diagnostic disable-next-line: missing-fields
  w, h = hover_float.dimensions({ max_cols = 1, max_rows = 1 })
  H.ok(w >= 1, "Breite ist nie 0")
  H.ok(h >= 1, "Höhe ist nie 0")

  -- ── Kein offenes Fenster: is_open/close sind sichere No-ops ────────────────
  H.falsy(hover_float.is_open(), "kein Hover-Float offen")
  hover_float.close() -- darf nicht fehlschlagen
  H.falsy(hover_float.is_open(), "close() bleibt ein No-op ohne offenes Fenster")
end
