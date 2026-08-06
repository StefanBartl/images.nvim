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

  -- ── box(): zentriert statt in der Ecke ──────────────────────────────────────
  local cols, rows, col_off, row_off = scale.box(100, 40, 1)
  H.eq(cols, 100, "factor=1 nutzt die volle Breite")
  H.eq(rows, 40, "…und volle Höhe")
  H.eq(col_off, 0, "…ohne Versatz")
  H.eq(row_off, 0, "…in beiden Achsen")

  cols, rows, col_off, row_off = scale.box(100, 40, 0.5)
  H.eq(cols, 50, "factor=0.5 halbiert die Breite")
  H.eq(rows, 20, "…und die Höhe")
  H.eq(col_off, 25, "…und zentriert horizontal ((100-50)/2)")
  H.eq(row_off, 10, "…und vertikal ((40-20)/2)")

  -- ── box(): nie kleiner als eine Zelle, auch bei extremem Faktor ────────────
  cols, rows = scale.box(10, 10, 0.01)
  H.ok(cols >= 1, "cols wird nie 0")
  H.ok(rows >= 1, "rows wird nie 0")
end
