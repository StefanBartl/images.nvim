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

  -- ── is_pdf / is_previewable: the second half of "is this one of yours" ───
  -- pdfport.nvim is not on the test runtimepath and pdftoppm is not a build
  -- dependency, so `is_pdf` is expected to answer NO here -- which is the
  -- interesting direction anyway: a machine that cannot rasterize must leave
  -- the PDF to the host rather than claim it and draw nothing.
  H.eq(type(picker.is_pdf("/tmp/report.pdf")), "boolean", "is_pdf() answers with a boolean")
  H.falsy(picker.is_pdf("/tmp/shot.png"), "a png is not a PDF")
  H.falsy(picker.is_pdf(nil), "nil is not a PDF")

  H.ok(picker.is_previewable("/tmp/shot.png"), "an image is previewable")
  H.falsy(picker.is_previewable("/tmp/notes.md"), "markdown is not previewable")
  H.eq(
    picker.is_previewable("/tmp/report.pdf"),
    picker.is_pdf("/tmp/report.pdf"),
    "a PDF is previewable exactly when it can be rasterized"
  )

  -- ── extensions(): still the image list, PDFs deliberately not in it ──────
  H.falsy(vim.tbl_contains(picker.extensions(), "pdf"), "pdf is not among the extensions")

  -- ── preview(): a PDF without a rasterizer says so, rather than "not an
  --    image" -- the two send a host looking in different places ────────────
  if not picker.is_pdf("/tmp/report.pdf") then
    local pok, perr = picker.preview(vim.api.nvim_get_current_win(), "/tmp/report.pdf")
    H.falsy(pok, "a PDF is refused without a rasterizer")
    H.contains(perr or "", "pdftoppm", "the error names what is missing")
  end

  -- ── clear(): safe with nothing on screen ─────────────────────────────────
  picker.clear()
end
