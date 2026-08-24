-- TESTS/zen_spec.lua — window size arithmetic for `:Image zen`.
--
-- `M.dimensions` is pure arithmetic over `vim.o.columns`/`vim.o.lines` without
-- opening a window — testable like `images.gallery`'s grid layout. The drawing
-- itself (`images.terminal.draw`) stays unchecked, as everywhere in this suite.

---@param H table harness from TESTS/run.lua
return function(H)
  local zen = require("images.zen")

  -- ── Default fractions ────────────────────────────────────────────────────
  local w, h = zen.dimensions(nil)
  H.eq(w, math.floor(vim.o.columns * 0.9), "default width: 90% of the editor width")
  H.eq(h, math.floor(vim.o.lines * 0.85), "default height: 85% of the editor height")

  -- ── Configured fractions ─────────────────────────────────────────────────
  w, h = zen.dimensions({ width = 0.5, height = 0.5 })
  H.eq(w, math.floor(vim.o.columns * 0.5), "a configured width is honoured")
  H.eq(h, math.floor(vim.o.lines * 0.5), "a configured height is honoured")

  -- ── Never smaller than 1 cell, even at a fraction of 0 ───────────────────
  w, h = zen.dimensions({ width = 0, height = 0 })
  H.eq(w, 1, "the width has a lower bound of 1")
  H.eq(h, 1, "the height has a lower bound of 1")

  -- ── No window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(zen.is_open(), "no zen window is open")
  zen.close() -- must not fail
  H.falsy(zen.is_open(), "close() stays a no-op without an open window")

  -- ── `dimensions_for` shrinks to the image's aspect ratio ─────────────────
  -- No real file access needed: without ImageMagick (or for a non-existent
  -- path) `images.info.collect` simply returns no `width`/`height`, and
  -- `dimensions_for` then falls back to the maximum box — exactly the path
  -- checked here without a terminal or ImageMagick.
  local max_w, max_h = zen.dimensions(nil)
  local fw, fh = zen.dimensions_for("/path/that/does/not/exist.png", nil)
  H.eq(fw, max_w, "without discoverable pixel dimensions: the width stays the maximum box")
  H.eq(fh, max_h, "without discoverable pixel dimensions: the height stays the maximum box")
end
