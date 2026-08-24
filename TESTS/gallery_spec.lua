-- TESTS/gallery_spec.lua — laying several images out on a grid.
--
-- `images.gallery` only computes and never draws; that is what makes it fully
-- testable headless. It is exactly what the separation from `images.terminal`
-- is for, which `scripts/gen_map.lua` enforces as a layer rule.

---@param H table harness from TESTS/run.lua
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

  -- ── Empty input ──────────────────────────────────────────────────────────
  local placements, skipped = gallery.layout({}, opts())
  H.eq(#placements, 0, "no images -> no placements")
  H.eq(skipped, 0, "no images -> nothing skipped")

  -- ── One image takes up the whole area ────────────────────────────────────
  placements = gallery.layout({ "a.png" }, opts())
  H.eq(#placements, 1, "one image -> one placement")
  H.eq(placements[1].row, 1, "starts on the given row")
  H.eq(placements[1].col, 1, "starts in the given column")
  H.eq(placements[1].cols, 100, "one image uses the full width")
  H.eq(placements[1].rows, 40, "one image uses the full height")

  -- ── Two images side by side, the gap subtracted ──────────────────────────
  placements = gallery.layout({ "a.png", "b.png" }, opts())
  H.eq(#placements, 2, "two images -> two placements")
  H.eq(placements[1].row, placements[2].row, "two images sit on one row")
  H.eq(placements[1].cols, 49, "width = (100 - 1 gap) / 2")
  H.eq(placements[2].col, 1 + 49 + 1, "the second tile sits after tile plus gap")

  -- ── Four images make two rows ────────────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png", "c.png", "d.png" }, opts())
  H.eq(#placements, 4, "four images -> four placements")
  H.eq(placements[1].row, placements[2].row, "the first row shares one line")
  H.ok(placements[3].row > placements[1].row, "the third tile starts a new row")
  H.eq(placements[1].col, placements[3].col, "columns line up across the rows")

  -- ── The column count can be capped ───────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png", "c.png" }, opts({ columns = 1 }))
  H.eq(#placements, 3, "columns=1 still shows all three")
  H.eq(placements[1].col, placements[2].col, "columns=1 -> all in one column")
  H.ok(placements[2].row > placements[1].row, "columns=1 -> each tile one row lower")

  -- More columns than images would mean an empty column; that is capped.
  placements = gallery.layout({ "a.png" }, opts({ columns = 5 }))
  H.eq(#placements, 1, "columns > count -> capped to the count")
  H.eq(placements[1].cols, 100, "and therefore back to the full width")

  -- ── Too little room yields nothing rather than illegible tiles ───────────
  local files = {}
  for i = 1, 16 do
    files[i] = ("f%d.png"):format(i)
  end
  placements, skipped = gallery.layout(files, opts({ width = 20, height = 8 }))
  H.eq(#placements, 0, "too little room -> no placement")
  H.eq(skipped, 16, "…and all of them reported as skipped")

  -- ── The starting point is honoured ───────────────────────────────────────
  placements = gallery.layout({ "a.png" }, opts({ top = 5, left = 10 }))
  H.eq(placements[1].row, 5, "top is honoured")
  H.eq(placements[1].col, 10, "left is honoured")

  -- ── No gap ───────────────────────────────────────────────────────────────
  placements = gallery.layout({ "a.png", "b.png" }, opts({ gap = 0 }))
  H.eq(placements[1].cols, 50, "gap=0 -> a full half per tile")
  H.eq(placements[2].col, 51, "gap=0 -> the tiles meet")
end
