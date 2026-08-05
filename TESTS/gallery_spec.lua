-- TESTS/gallery_spec.lua — Rasteraufteilung mehrerer Bilder.
--
-- `images.gallery` rechnet nur und zeichnet nicht; deshalb ist es headless
-- vollständig prüfbar. Genau dafür ist die Trennung von `images.terminal` da,
-- die `scripts/gen_map.lua` als Layer-Regel absichert.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local gallery = require("images.gallery")

  local function opts(over)
    return vim.tbl_extend("force", {
      gap = 1,
      top = 1,
      left = 1,
      width = 100,
      height = 40,
    }, over or {})
  end

  -- ── Leere Eingabe ──────────────────────────────────────────────────────────
  local placements, skipped = gallery.layout({}, opts())
  H.eq(#placements, 0, "keine Bilder → keine Platzierungen")
  H.eq(skipped, 0, "keine Bilder → nichts übersprungen")

  -- ── Ein Bild belegt die volle Fläche ───────────────────────────────────────
  placements = gallery.layout({ "a.png" }, opts())
  H.eq(#placements, 1, "ein Bild → eine Platzierung")
  H.eq(placements[1].row, 1, "startet in der vorgegebenen Zeile")
  H.eq(placements[1].col, 1, "startet in der vorgegebenen Spalte")
  H.eq(placements[1].cols, 100, "ein Bild nutzt die volle Breite")
  H.eq(placements[1].rows, 40, "ein Bild nutzt die volle Höhe")

  -- ── Zwei Bilder nebeneinander, Lücke abgezogen ─────────────────────────────
  placements = gallery.layout({ "a.png", "b.png" }, opts())
  H.eq(#placements, 2, "zwei Bilder → zwei Platzierungen")
  H.eq(placements[1].row, placements[2].row, "zwei Bilder stehen in einer Zeile")
  H.eq(placements[1].cols, 49, "Breite = (100 - 1 Lücke) / 2")
  H.eq(placements[2].col, 1 + 49 + 1, "zweite Kachel hinter Kachel plus Lücke")

  -- ── Vier Bilder ergeben zwei Reihen ────────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png", "c.png", "d.png" }, opts())
  H.eq(#placements, 4, "vier Bilder → vier Platzierungen")
  H.eq(placements[1].row, placements[2].row, "erste Reihe teilt sich die Zeile")
  H.ok(placements[3].row > placements[1].row, "dritte Kachel beginnt eine neue Reihe")
  H.eq(placements[1].col, placements[3].col, "Spalten fluchten über die Reihen")

  -- ── Spaltenzahl ist deckelbar ──────────────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png", "c.png" }, opts({ columns = 1 }))
  H.eq(#placements, 3, "columns=1 zeigt trotzdem alle drei")
  H.eq(placements[1].col, placements[2].col, "columns=1 → alle in einer Spalte")
  H.ok(placements[2].row > placements[1].row, "columns=1 → jede Kachel eine Reihe tiefer")

  -- Mehr Spalten als Bilder wären eine leere Spalte; das wird gekappt.
  placements = gallery.layout({ "a.png" }, opts({ columns = 5 }))
  H.eq(#placements, 1, "columns > Anzahl → auf die Anzahl gekappt")
  H.eq(placements[1].cols, 100, "und damit wieder volle Breite")

  -- ── Zu wenig Platz liefert nichts statt unlesbarer Kacheln ─────────────────
  local files = {}
  for i = 1, 16 do
    files[i] = ("f%d.png"):format(i)
  end
  placements, skipped = gallery.layout(files, opts({ width = 20, height = 8 }))
  H.eq(#placements, 0, "zu wenig Platz → keine Platzierung")
  H.eq(skipped, 16, "…und alle als übersprungen gemeldet")

  -- ── Startpunkt wird respektiert ────────────────────────────────────────────
  placements = gallery.layout({ "a.png" }, opts({ top = 5, left = 10 }))
  H.eq(placements[1].row, 5, "top wird übernommen")
  H.eq(placements[1].col, 10, "left wird übernommen")

  -- ── Keine Lücke ────────────────────────────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png" }, opts({ gap = 0 }))
  H.eq(placements[1].cols, 50, "gap=0 → volle Hälfte je Kachel")
  H.eq(placements[2].col, 51, "gap=0 → Kacheln stoßen aneinander")
end
