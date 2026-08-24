-- TESTS/hover_float_spec.lua — window size arithmetic for the hover float.
--
-- The same restraint as zen_spec.lua: `M.dimensions` is pure arithmetic over
-- `vim.o.columns`/`vim.o.lines` without opening a window — testable. The
-- drawing itself (`images.terminal.draw`, triggered by a real `M.open()`)
-- stays unchecked, as everywhere in this suite.

---@param H table harness from TESTS/run.lua
return function(H)
  local hover_float = require("images.hover_float")

  -- ── Within the editor size: max_cols/max_rows win unchanged ──────────────
  ---@diagnostic disable-next-line: missing-fields
  local w, h = hover_float.dimensions({ max_cols = 40, max_rows = 15 })
  H.eq(w, 40, "a width below the editor size stays unchanged")
  H.eq(h, 15, "a height below the editor size stays unchanged")

  -- ── Larger than the editor: capped to the editor size minus a margin ─────
  ---@diagnostic disable-next-line: missing-fields
  w, h = hover_float.dimensions({ max_cols = vim.o.columns * 10, max_rows = vim.o.lines * 10 })
  H.eq(w, math.max(1, vim.o.columns - 4), "the width is capped to the editor width")
  H.eq(h, math.max(1, vim.o.lines - 4), "the height is capped to the editor height")

  -- ── Never smaller than 1 cell ────────────────────────────────────────────
  ---@diagnostic disable-next-line: missing-fields
  w, h = hover_float.dimensions({ max_cols = 1, max_rows = 1 })
  H.ok(w >= 1, "the width is never 0")
  H.ok(h >= 1, "the height is never 0")

  -- ── No window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(hover_float.is_open(), "no hover float is open")
  hover_float.close() -- must not fail
  H.falsy(hover_float.is_open(), "close() stays a no-op without an open window")
end
