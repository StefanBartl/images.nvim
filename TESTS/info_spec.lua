-- TESTS/info_spec.lua — Metadaten-Formatierung.
--
-- `collect` liest das Dateisystem und ruft optional ImageMagick; geprüft wird
-- hier die reine Aufbereitung plus das Verhalten bei fehlender Datei.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local info = require("images.info")

  -- ── human_size ─────────────────────────────────────────────────────────────
  H.eq(info.human_size(0), "0 B", "null Bytes")
  H.eq(info.human_size(512), "512 B", "unter 1 KB bleibt in Bytes, ohne Nachkommastelle")
  H.eq(info.human_size(1024), "1.0 KB", "genau 1 KB kippt in die nächste Einheit")
  H.eq(info.human_size(1536), "1.5 KB", "Nachkommastelle bei Bruchteilen")
  H.eq(info.human_size(1024 * 1024), "1.0 MB", "Megabyte")
  H.eq(info.human_size(1024 * 1024 * 1024), "1.0 GB", "Gigabyte")
  -- Über GB wird nicht weiter skaliert: die Einheitenliste endet dort, und ein
  -- Bild jenseits davon ist ohnehin ein Sonderfall.
  H.contains(info.human_size(5 * 1024 * 1024 * 1024), "GB", "oberhalb GB bleibt es bei GB")

  -- ── collect meldet fehlende Dateien statt zu werfen ────────────────────────
  local data, err = info.collect("/definitiv/nicht/vorhanden.png")
  H.falsy(data, "fehlende Datei liefert keine Daten")
  H.contains(err or "", "nicht gefunden", "…sondern eine Begründung")

  -- ── lines() auf einem Datensatz ohne Abmessungen ───────────────────────────
  -- Der Fall ohne ImageMagick: Größe und Datum müssen trotzdem herauskommen,
  -- sonst wäre das Feature ohne die optionale Abhängigkeit wertlos.
  local lines = info.lines({
    path = "/tmp/x.png",
    bytes = 2048,
    mtime = 0,
    format = nil,
    width = nil,
    height = nil,
  })
  H.ok(#lines >= 2, "mindestens Pfad und Größe")
  H.contains(table.concat(lines, "\n"), "2.0 KB", "Größe erscheint formatiert")

  -- ── lines() mit Abmessungen ────────────────────────────────────────────────
  lines = info.lines({
    path = "/tmp/x.png",
    bytes = 100,
    mtime = 0,
    format = "PNG",
    width = 200,
    height = 100,
  })
  local joined = table.concat(lines, "\n")
  H.contains(joined, "PNG 200x100", "Format und Abmessungen in einer Zeile")
end
