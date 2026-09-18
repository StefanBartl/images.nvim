-- TESTS/ascii_spec.lua — `images.ascii`, only the safely testable part.
--
-- `M.open()` opens a real window and paints block graphics into it (needs
-- ImageMagick and a real image) — that stays unchecked here, like
-- `images.redact.open()` in redact_spec.lua. The sampling/painting it draws
-- through is covered in blocks_spec.lua.

---@param H table harness from TESTS/run.lua
return function(H)
  local ascii = require("images.ascii")

  -- ── no window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(ascii.is_open(), "no ASCII window is open")
  ascii.close() -- must not fail
  H.falsy(ascii.is_open(), "close() stays a no-op without an open window")

  -- ── available(): a real, side-effect-free check (magick on PATH) ─────────
  local available = ascii.available()
  H.eq(type(available), "boolean", "available() reports a boolean either way")
end
