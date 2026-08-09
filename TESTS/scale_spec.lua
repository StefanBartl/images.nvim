-- TESTS/scale_spec.lua — relative Bildskalierung für `:Image compare`.
--
-- Reine Berechnung, kein Terminal nötig — dieselbe Trennung wie
-- `images.gallery`.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local scale = require("images.scale")

  -- ── Ohne Maße: bisheriges Verhalten, beide füllen ihre Pane ────────────────
  local r = scale.compute(nil, nil)
  H.eq(r.a, 1, "fehlende Maße → a=1 (voller Pane, wie vor dem Feature)")
  H.eq(r.b, 1, "…und b=1")

  r = scale.compute({ width = 100, height = 100 }, nil)
  H.eq(r.a, 1, "nur ein Maß bekannt → beide 1 (nicht vergleichbar)")
  H.eq(r.b, 1, "…kein einseitiges Raten")

  -- ── Gleich große Bilder: keine Skalierung ──────────────────────────────────
  r = scale.compute({ width = 800, height = 600 }, { width = 800, height = 600 })
  H.eq(r.a, 1, "identische Maße → a=1")
  H.eq(r.b, 1, "…und b=1")

  -- ── A deutlich größer als B ─────────────────────────────────────────────────
  -- Diagonale A = sqrt(4000²+3000²) = 5000, Diagonale B = sqrt(200²+150²) = 250.
  -- ratio = 250/5000 = 0.05, unter MIN_SCALE → auf MIN_SCALE gekappt.
  r = scale.compute({ width = 4000, height = 3000 }, { width = 200, height = 150 })
  H.eq(r.a, 1, "das größere Bild bleibt bei voller Pane")
  H.eq(r.b, scale.MIN_SCALE, "das viel kleinere Bild wird auf den Mindestfaktor gekappt")

  -- ── B größer als A (Seitenvertauschung) ─────────────────────────────────────
  r = scale.compute({ width = 200, height = 150 }, { width = 4000, height = 3000 })
  H.eq(r.a, scale.MIN_SCALE, "die Rollen tauschen korrekt mit den Argumenten")
  H.eq(r.b, 1, "…B ist jetzt das größere")

  -- ── Moderater Unterschied bleibt oberhalb des Mindestfaktors ───────────────
  -- Diagonale A = sqrt(1000²+1000²) ≈ 1414, Diagonale B ≈ 707 (halb so groß).
  -- ratio = 0.5, klar über MIN_SCALE (0.35) → wird nicht gekappt.
  r = scale.compute({ width = 1000, height = 1000 }, { width = 500, height = 500 })
  H.eq(r.a, 1, "größeres Bild voll")
  H.ok(r.b > scale.MIN_SCALE, "moderater Größenunterschied wird nicht auf den Mindestfaktor gekappt")
  H.ok(r.b < 1, "…ist aber sichtbar kleiner als das größere Bild")
  H.eq(math.floor(r.b * 100 + 0.5), 50, "der Faktor entspricht dem tatsächlichen Diagonalenverhältnis (0.5)")

  -- ── anchor_box("center", ...): zentriert statt in der Ecke ─────────────────
  local cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center", 1)
  H.eq(cols, 100, "scale=1 nutzt die volle Breite")
  H.eq(rows, 40, "…und volle Höhe")
  H.eq(col_off, 0, "…ohne Versatz")
  H.eq(row_off, 0, "…in beiden Achsen")

  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center", 0.5)
  H.eq(cols, 50, "scale=0.5 halbiert die Breite")
  H.eq(rows, 20, "…und die Höhe")
  H.eq(col_off, 25, "…und zentriert horizontal ((100-50)/2)")
  H.eq(row_off, 10, "…und vertikal ((40-20)/2)")

  -- ── anchor_box("full", ...): scale wird ignoriert, immer volle Größe ───────
  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "full", 0.1)
  H.eq(cols, 100, "full ignoriert scale — volle Breite")
  H.eq(rows, 40, "…und volle Höhe")
  H.eq(col_off, 0, "…kein Versatz")
  H.eq(row_off, 0, "…in beiden Achsen")

  -- ── anchor_box(): die acht Randpositionen sitzen am jeweiligen Rand,
  --    mittig zentriert entlang der anderen Achse, nicht in der Ecke ────────
  local _
  _, _, col_off, row_off = scale.anchor_box(100, 40, "top-left", 0.5)
  H.eq(col_off, 0, "top-left: kein horizontaler Versatz")
  H.eq(row_off, 0, "top-left: kein vertikaler Versatz")

  cols, _, col_off, row_off = scale.anchor_box(100, 40, "top-right", 0.5)
  H.eq(col_off, 100 - cols, "top-right: an die rechte Kante")
  H.eq(row_off, 0, "top-right: oben")

  _, rows, col_off, row_off = scale.anchor_box(100, 40, "bottom-left", 0.5)
  H.eq(col_off, 0, "bottom-left: links")
  H.eq(row_off, 40 - rows, "bottom-left: an die untere Kante")

  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center-right", 0.5)
  H.eq(col_off, 100 - cols, "center-right: rechte Kante")
  H.eq(row_off, math.floor((40 - rows) / 2), "center-right: vertikal zentriert")

  -- ── anchor_box(): nie kleiner als eine Zelle, auch bei extremem Skalar ─────
  cols, rows = scale.anchor_box(10, 10, "center", 0.01)
  H.ok(cols >= 1, "cols wird nie 0")
  H.ok(rows >= 1, "rows wird nie 0")

  -- ── anchor_box(): unbekannte Position meldet einen Fehler statt zu raten ──
  local nil_cols, _, _, _, err = scale.anchor_box(100, 40, "nowhere", 0.5)
  H.eq(nil_cols, nil, "unbekannte Position liefert kein Ergebnis")
  H.ok(err ~= nil, "…sondern eine Fehlermeldung")
  H.contains(err, "nowhere", "…die die ungültige Eingabe nennt")

  -- ── fit_cells(): ohne Bildmaße unverändert ─────────────────────────────────
  cols, rows = scale.fit_cells(60, 25, nil)
  H.eq(cols, 60, "ohne Maße: max_cols unverändert")
  H.eq(rows, 25, "…und max_rows")

  -- ── fit_cells(): quadratisches Bild, Zelle 2x höher als breit (CELL_ASPECT
  --    0.5) → cols/rows soll 2 sein, damit das Bild wirklich quadratisch
  --    aussieht ─────────────────────────────────────────────────────────────
  cols, rows = scale.fit_cells(60, 25, { width = 100, height = 100 })
  H.eq(rows, 25, "Höhe bleibt am Maximum")
  H.eq(cols, 50, "Breite wird auf image_aspect/CELL_ASPECT = 2x die Höhe gesetzt")

  -- ── fit_cells(): sehr breites Bild kappt an max_cols, Höhe schrumpft ───────
  cols, rows = scale.fit_cells(60, 25, { width = 4000, height = 1000 })
  H.eq(cols, 60, "Breite bleibt am Maximum")
  H.ok(rows < 25, "Höhe schrumpft, damit das Seitenverhältnis stimmt")

  -- ── fit_cells(): sehr hohes Bild kappt an max_rows, Breite schrumpft ───────
  cols, rows = scale.fit_cells(60, 25, { width = 1000, height = 4000 })
  H.eq(rows, 25, "Höhe bleibt am Maximum")
  H.ok(cols < 60, "Breite schrumpft, damit das Seitenverhältnis stimmt")

  -- ── fit_cells(): nie kleiner als eine Zelle ─────────────────────────────────
  cols, rows = scale.fit_cells(1, 1, { width = 1, height = 1000 })
  H.ok(cols >= 1, "cols wird nie 0")
  H.ok(rows >= 1, "rows wird nie 0")

  -- ── cell_box_to_pixels(): lineare Umrechnung ohne Marge ────────────────────
  local px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 5, col2 = 10 }, 50, 25, { width = 500, height = 250 }, 0)
  H.eq(px.x1, 0, "linke obere Ecke bei Zelle 1 → Pixel 0")
  H.eq(px.y1, 0, "…und oben")
  H.eq(px.x2, 100, "rechte Kante: Zelle 10 von 50 → 10/50*500 = 100")
  H.eq(px.y2, 50, "untere Kante: Zelle 5 von 25 → 5/25*250 = 50")

  -- ── cell_box_to_pixels(): Sicherheitsmarge wächst die Box, aber nie über
  --    den Bildrand hinaus ──────────────────────────────────────────────────
  px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 5, col2 = 10 }, 50, 25, { width = 500, height = 250 }, 1)
  H.eq(px.x1, 0, "Marge an der linken Kante bleibt bei 0, nicht negativ")
  H.eq(px.y1, 0, "…dieselbe Deckelung oben")
  H.eq(px.x2, 110, "Marge erweitert die rechte Kante um eine Zelle (11/50*500)")

  -- ── cell_box_to_pixels(): niemals über die Bildmaße hinaus, auch bei
  --    übertriebener Marge ────────────────────────────────────────────────────
  px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 25, col2 = 50 }, 50, 25, { width = 500, height = 250 }, 100)
  H.eq(px.x2, 500, "x2 wird auf die Bildbreite gedeckelt")
  H.eq(px.y2, 250, "y2 wird auf die Bildhöhe gedeckelt")
end
