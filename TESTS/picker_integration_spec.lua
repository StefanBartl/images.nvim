-- TESTS/picker_integration_spec.lua — the surface foreign pickers consume.
--
-- Same restraint as the rest of the suite: everything up to the draw is
-- checked, the draw itself is not (it needs a terminal speaking OSC 1337).
-- That split is exactly why `M.preview` rejects an unusable window and a
-- non-image path BEFORE it touches the draw path — those two guards are what
-- a host branches on, so they are the two that must hold headlessly.

---@param H table harness from TESTS/run.lua
return function(H)
  local picker = require("images.integrations.picker")

  -- ── is_image: the configured extensions, nothing else ────────────────────
  H.ok(picker.is_image("/tmp/shot.png"), "png is an image")
  H.ok(picker.is_image("C:/pics/Holiday.JPEG"), "the extension check is case-insensitive")
  H.falsy(picker.is_image("/tmp/notes.md"), "markdown is not an image")
  H.falsy(picker.is_image("/tmp/README"), "an extensionless file is not an image")
  H.falsy(picker.is_image(nil), "nil is not an image")
  H.falsy(picker.is_image(""), "the empty string is not an image")

  -- ── extensions(): a copy, so a host may filter it destructively ──────────
  local exts = picker.extensions()
  H.ok(vim.tbl_contains(exts, "png"), "png is among the configured extensions")
  exts[#exts + 1] = "xyz"
  H.falsy(vim.tbl_contains(picker.extensions(), "xyz"), "the returned list is a copy")

  -- ── available(): a strict yes/no, never nil (a host branches on it) ──────
  H.eq(type(picker.available()), "boolean", "available() answers with a boolean")

  -- ── preview(): the two rejections that happen before any drawing ─────────
  local ok, err = picker.preview(999999, "/tmp/shot.png")
  H.falsy(ok, "an invalid window is rejected")
  H.contains(err or "", "not a valid window", "the error names the window")

  ok, err = picker.preview(vim.api.nvim_get_current_win(), "/tmp/notes.md")
  H.falsy(ok, "a non-image entry is rejected")
  H.contains(err or "", "not an image", "the error names the reason")

  -- ── clear(): safe with nothing on screen ─────────────────────────────────
  picker.clear()
end
