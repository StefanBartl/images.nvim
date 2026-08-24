-- TESTS/scale_spec.lua — relative image scaling for `:Image compare`.
--
-- Pure computation, no terminal needed — the same separation as
-- `images.gallery`.

---@param H table harness from TESTS/run.lua
return function(H)
  local scale = require("images.scale")

  -- ── Without dimensions: previous behaviour, both fill their pane ─────────
  local r = scale.compute(nil, nil)
  H.eq(r.a, 1, "missing dimensions -> a=1 (full pane, as before the feature)")
  H.eq(r.b, 1, "…and b=1")

  r = scale.compute({ width = 100, height = 100 }, nil)
  H.eq(r.a, 1, "only one dimension known -> both 1 (not comparable)")
  H.eq(r.b, 1, "…no one-sided guessing")

  -- ── Equally sized images: no scaling ─────────────────────────────────────
  r = scale.compute({ width = 800, height = 600 }, { width = 800, height = 600 })
  H.eq(r.a, 1, "identical dimensions -> a=1")
  H.eq(r.b, 1, "…and b=1")

  -- ── A much larger than B ─────────────────────────────────────────────────
  -- Diagonal A = sqrt(4000²+3000²) = 5000, diagonal B = sqrt(200²+150²) = 250.
  -- ratio = 250/5000 = 0.05, below MIN_SCALE -> clamped to MIN_SCALE.
  r = scale.compute({ width = 4000, height = 3000 }, { width = 200, height = 150 })
  H.eq(r.a, 1, "the larger image keeps its full pane")
  H.eq(r.b, scale.MIN_SCALE, "the far smaller image is clamped to the minimum factor")

  -- ── B larger than A (arguments swapped) ──────────────────────────────────
  r = scale.compute({ width = 200, height = 150 }, { width = 4000, height = 3000 })
  H.eq(r.a, scale.MIN_SCALE, "the roles swap correctly with the arguments")
  H.eq(r.b, 1, "…B is now the larger one")

  -- ── A moderate difference stays above the minimum factor ─────────────────
  -- Diagonal A = sqrt(1000²+1000²) ≈ 1414, diagonal B ≈ 707 (half the size).
  -- ratio = 0.5, well above MIN_SCALE (0.35) -> not clamped.
  r = scale.compute({ width = 1000, height = 1000 }, { width = 500, height = 500 })
  H.eq(r.a, 1, "the larger image at full size")
  H.ok(r.b > scale.MIN_SCALE, "a moderate size difference is not clamped to the minimum factor")
  H.ok(r.b < 1, "…but is visibly smaller than the larger image")
  H.eq(math.floor(r.b * 100 + 0.5), 50, "the factor matches the actual diagonal ratio (0.5)")

  -- ── anchor_box("center", ...): centred rather than in the corner ─────────
  local cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center", 1)
  H.eq(cols, 100, "scale=1 uses the full width")
  H.eq(rows, 40, "…and the full height")
  H.eq(col_off, 0, "…with no offset")
  H.eq(row_off, 0, "…on either axis")

  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center", 0.5)
  H.eq(cols, 50, "scale=0.5 halves the width")
  H.eq(rows, 20, "…and the height")
  H.eq(col_off, 25, "…and centres horizontally ((100-50)/2)")
  H.eq(row_off, 10, "…and vertically ((40-20)/2)")

  -- ── anchor_box("full", ...): scale is ignored, always the full size ──────
  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "full", 0.1)
  H.eq(cols, 100, "full ignores scale — the full width")
  H.eq(rows, 40, "…and the full height")
  H.eq(col_off, 0, "…no offset")
  H.eq(row_off, 0, "…on either axis")

  -- ── anchor_box(): the eight edge positions sit against their edge, centred
  --    along the other axis rather than glued into the corner ──────────────
  local _
  _, _, col_off, row_off = scale.anchor_box(100, 40, "top-left", 0.5)
  H.eq(col_off, 0, "top-left: no horizontal offset")
  H.eq(row_off, 0, "top-left: no vertical offset")

  cols, _, col_off, row_off = scale.anchor_box(100, 40, "top-right", 0.5)
  H.eq(col_off, 100 - cols, "top-right: against the right edge")
  H.eq(row_off, 0, "top-right: at the top")

  _, rows, col_off, row_off = scale.anchor_box(100, 40, "bottom-left", 0.5)
  H.eq(col_off, 0, "bottom-left: on the left")
  H.eq(row_off, 40 - rows, "bottom-left: against the bottom edge")

  cols, rows, col_off, row_off = scale.anchor_box(100, 40, "center-right", 0.5)
  H.eq(col_off, 100 - cols, "center-right: the right edge")
  H.eq(row_off, math.floor((40 - rows) / 2), "center-right: vertically centred")

  -- ── anchor_box(): never smaller than one cell, even at an extreme scale ──
  cols, rows = scale.anchor_box(10, 10, "center", 0.01)
  H.ok(cols >= 1, "cols is never 0")
  H.ok(rows >= 1, "rows is never 0")

  -- ── anchor_box(): an unknown position reports an error rather than guess ─
  local nil_cols, _, _, _, err = scale.anchor_box(100, 40, "nowhere", 0.5)
  H.eq(nil_cols, nil, "an unknown position yields no result")
  H.ok(err ~= nil, "…but an error message")
  H.contains(err, "nowhere", "…which names the invalid input")

  -- ── fit_cells(): unchanged without image dimensions ──────────────────────
  cols, rows = scale.fit_cells(60, 25, nil)
  H.eq(cols, 60, "without dimensions: max_cols unchanged")
  H.eq(rows, 25, "…and max_rows")

  -- ── fit_cells(): a square image with cells twice as tall as wide
  --    (CELL_ASPECT 0.5) -> cols/rows should be 2, so the image really looks
  --    square ───────────────────────────────────────────────────────────────
  cols, rows = scale.fit_cells(60, 25, { width = 100, height = 100 })
  H.eq(rows, 25, "the height stays at the maximum")
  H.eq(cols, 50, "the width is set to image_aspect/CELL_ASPECT = 2x the height")

  -- ── fit_cells(): a very wide image caps at max_cols, the height shrinks ──
  cols, rows = scale.fit_cells(60, 25, { width = 4000, height = 1000 })
  H.eq(cols, 60, "the width stays at the maximum")
  H.ok(rows < 25, "the height shrinks so the aspect ratio holds")

  -- ── fit_cells(): a very tall image caps at max_rows, the width shrinks ───
  cols, rows = scale.fit_cells(60, 25, { width = 1000, height = 4000 })
  H.eq(rows, 25, "the height stays at the maximum")
  H.ok(cols < 60, "the width shrinks so the aspect ratio holds")

  -- ── fit_cells(): never smaller than one cell ─────────────────────────────
  cols, rows = scale.fit_cells(1, 1, { width = 1, height = 1000 })
  H.ok(cols >= 1, "cols is never 0")
  H.ok(rows >= 1, "rows is never 0")

  -- ── cell_box_to_pixels(): a linear conversion without a margin ───────────
  local px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 5, col2 = 10 }, 50, 25, { width = 500, height = 250 }, 0)
  H.eq(px.x1, 0, "top left corner at cell 1 -> pixel 0")
  H.eq(px.y1, 0, "…and at the top")
  H.eq(px.x2, 100, "right edge: cell 10 of 50 -> 10/50*500 = 100")
  H.eq(px.y2, 50, "bottom edge: cell 5 of 25 -> 5/25*250 = 50")

  -- ── cell_box_to_pixels(): the safety margin grows the box, but never past
  --    the image's edge ─────────────────────────────────────────────────────
  px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 5, col2 = 10 }, 50, 25, { width = 500, height = 250 }, 1)
  H.eq(px.x1, 0, "the margin at the left edge stays at 0, never negative")
  H.eq(px.y1, 0, "…the same clamp at the top")
  H.eq(px.x2, 110, "the margin extends the right edge by one cell (11/50*500)")

  -- ── cell_box_to_pixels(): never past the image dimensions, even with an
  --    exaggerated margin ───────────────────────────────────────────────────
  px = scale.cell_box_to_pixels({ row1 = 1, col1 = 1, row2 = 25, col2 = 50 }, 50, 25, { width = 500, height = 250 }, 100)
  H.eq(px.x2, 500, "x2 is clamped to the image width")
  H.eq(px.y2, 250, "y2 is clamped to the image height")
end
