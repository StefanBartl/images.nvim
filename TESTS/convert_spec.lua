-- TESTS/convert_spec.lua — SVG-zu-PNG-Konvertierung.
--
-- `is_svg` ist reine Funktion. `to_png` braucht ein echtes Dateisystem und —
-- für den eigentlichen Konvertierungspfad — `magick`; ohne wird dieser Teil
-- übersprungen statt zu scheitern, dieselbe Haltung wie die Leitplanke
-- selbst ("ImageMagick verbessert, ermöglicht nicht").

---@param H table Harness aus TESTS/run.lua
return function(H)
  local convert = require("images.convert")

  -- ── is_svg ───────────────────────────────────────────────────────────────
  H.ok(convert.is_svg("bild.svg"), "svg wird erkannt")
  H.ok(convert.is_svg("BILD.SVG"), "…case-insensitiv")
  H.ok(convert.is_svg("a/b/c.svg"), "…unabhängig vom Pfad")
  H.falsy(convert.is_svg("bild.png"), "png ist kein svg")
  H.falsy(convert.is_svg("bild.svg.png"), "nur die letzte Endung zählt")

  -- ── to_png: fehlende Datei ──────────────────────────────────────────────────
  local png, err = convert.to_png("/definitiv/nicht/vorhanden.svg")
  H.falsy(png, "fehlende Datei liefert kein Ergebnis")
  H.contains(err or "", "nicht gefunden", "…sondern eine Begründung")

  if vim.fn.executable("magick") == 0 then
    -- Der eigentliche Konvertierungspfad ist ohne ImageMagick nicht sinnvoll
    -- prüfbar — genau der Fall, den die Leitplanke vorsieht.
    return
  end

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local svg_path = root .. "/test.svg"
  local fd = assert(io.open(svg_path, "w"))
  fd:write('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">' .. '<rect width="10" height="10" fill="red"/></svg>')
  fd:close()

  png, err = convert.to_png(svg_path)
  H.ok(png, "Konvertierung liefert einen Pfad: " .. tostring(err))
  H.ok(png ~= nil and vim.uv.fs_stat(png) ~= nil, "…und die Datei existiert wirklich")
  H.contains(png or "", ".png", "…mit .png-Endung")

  -- ── Cache: zweiter Aufruf liefert denselben Pfad, ohne neu zu konvertieren ──
  local png2 = convert.to_png(svg_path)
  H.eq(png2, png, "gleiche Quelle (gleiche mtime) trifft den Cache")

  -- ── Geänderte Quelle bekommt einen neuen Cache-Eintrag ─────────────────────
  -- mtime nur auf Sekundenbasis im Cache-Schlüssel — künstlich eine Sekunde
  -- vorstellen, damit der Test nicht von der Dateisystem-Auflösung abhängt.
  local future = os.time() + 2
  vim.uv.fs_utime(svg_path, future, future)
  local png3 = convert.to_png(svg_path)
  H.ok(png3 ~= nil, "erneute Konvertierung nach Änderung liefert einen Pfad")
  H.ok(png3 ~= png, "…aber unter einem anderen Cache-Namen als vorher")
end
