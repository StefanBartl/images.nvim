-- TESTS/zen_spec.lua — Fenstergrößen-Berechnung für `:Image zen`.
--
-- `M.dimensions` ist reine Mathematik über `vim.o.columns`/`vim.o.lines`,
-- ohne ein Fenster zu öffnen — testbar wie `images.gallery`'s Rasteraufteilung.
-- Das Zeichnen selbst (`images.terminal.draw`) bleibt ungeprüft, wie überall
-- in dieser Suite.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local zen = require("images.zen")

  -- ── Default-Anteile ─────────────────────────────────────────────────────────
  local w, h = zen.dimensions(nil)
  H.eq(w, math.floor(vim.o.columns * 0.9), "Default-Breite: 90% der Editorbreite")
  H.eq(h, math.floor(vim.o.lines * 0.85), "Default-Höhe: 85% der Editorhöhe")

  -- ── Konfigurierte Anteile ───────────────────────────────────────────────────
  w, h = zen.dimensions({ width = 0.5, height = 0.5 })
  H.eq(w, math.floor(vim.o.columns * 0.5), "konfigurierte Breite wird übernommen")
  H.eq(h, math.floor(vim.o.lines * 0.5), "konfigurierte Höhe wird übernommen")

  -- ── Nie kleiner als 1 Zelle, auch bei einem Anteil von 0 ───────────────────
  w, h = zen.dimensions({ width = 0, height = 0 })
  H.eq(w, 1, "Breite ist nach unten auf 1 gedeckelt")
  H.eq(h, 1, "Höhe ist nach unten auf 1 gedeckelt")

  -- ── Kein offenes Fenster: is_open/close sind sichere No-ops ────────────────
  H.falsy(zen.is_open(), "kein Zen-Fenster offen")
  zen.close() -- darf nicht fehlschlagen
  H.falsy(zen.is_open(), "close() bleibt ein No-op ohne offenes Fenster")

  -- ── `dimensions_for` schrumpft auf das Bild-Seitenverhältnis ───────────────
  -- Kein echter Dateizugriff nötig: `images.info.collect` liefert ohne
  -- ImageMagick (oder für einen nicht existierenden Pfad) einfach kein
  -- `width`/`height`, und `dimensions_for` fällt dann auf die Maximalbox
  -- zurück — exakt der Pfad, der hier ohne Terminal/ImageMagick geprüft wird.
  local max_w, max_h = zen.dimensions(nil)
  local fw, fh = zen.dimensions_for("/pfad/der/nicht/existiert.png", nil)
  H.eq(fw, max_w, "ohne ermittelbare Pixelmaße: Breite bleibt die Maximalbox")
  H.eq(fh, max_h, "ohne ermittelbare Pixelmaße: Höhe bleibt die Maximalbox")
end
