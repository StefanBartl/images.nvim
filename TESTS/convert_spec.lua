-- TESTS/convert_spec.lua — SVG->PNG, image->PDF, image->redacted copy.
--
-- `is_svg` is a pure function. `to_png`/`to_pdf`/`redact` need a real
-- filesystem and — for the actual conversion path — `magick`; without it that
-- part is skipped rather than failed, the same stance as the guardrail itself
-- ("ImageMagick improves, never enables" — `to_pdf`/`redact` are its
-- documented exceptions, but without `magick` at all there is nothing
-- meaningful to check here).

---@param H table harness from TESTS/run.lua
return function(H)
  local convert = require("images.convert")

  -- ── is_svg ───────────────────────────────────────────────────────────────
  H.ok(convert.is_svg("image.svg"), "svg is recognised")
  H.ok(convert.is_svg("IMAGE.SVG"), "…case-insensitively")
  H.ok(convert.is_svg("a/b/c.svg"), "…regardless of the path")
  H.falsy(convert.is_svg("image.png"), "png is not svg")
  H.falsy(convert.is_svg("image.svg.png"), "only the last extension counts")

  -- ── to_png: missing file ─────────────────────────────────────────────────
  local png, err = convert.to_png("/definitely/does/not/exist.svg")
  H.falsy(png, "a missing file yields no result")
  H.contains(err or "", "not found", "…but a reason")

  if vim.fn.executable("magick") == 0 then
    -- The actual conversion path cannot be checked meaningfully without
    -- ImageMagick -- exactly the case the guardrail anticipates.
    return
  end

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local svg_path = root .. "/test.svg"
  local fd = assert(io.open(svg_path, "w"))
  fd:write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">' .. '<rect width="10" height="10" fill="red"/></svg>'
  )
  fd:close()

  png, err = convert.to_png(svg_path)
  H.ok(png, "conversion yields a path: " .. tostring(err))
  H.ok(png ~= nil and vim.uv.fs_stat(png) ~= nil, "…and the file really exists")
  H.contains(png or "", ".png", "…with a .png extension")

  -- ── Cache: a second call returns the same path without reconverting ──────
  local png2 = convert.to_png(svg_path)
  H.eq(png2, png, "the same source (same mtime) hits the cache")

  -- ── A changed source gets a new cache entry ──────────────────────────────
  -- The cache key carries mtime at second resolution only -- move it forward
  -- artificially by a second so the test does not depend on the filesystem's
  -- timestamp granularity.
  local future = os.time() + 2
  vim.uv.fs_utime(svg_path, future, future)
  local png3 = convert.to_png(svg_path)
  H.ok(png3 ~= nil, "reconverting after a change yields a path")
  H.ok(png3 ~= png, "…but under a different cache name than before")

  -- ── to_pdf: missing file ─────────────────────────────────────────────────
  local pdf, pdf_err = convert.to_pdf("/definitely/does/not/exist.png")
  H.falsy(pdf, "a missing file yields no PDF")
  H.contains(pdf_err or "", "not found", "…but a reason")

  -- ── to_pdf: real conversion ──────────────────────────────────────────────
  pdf, pdf_err = convert.to_pdf(assert(png))
  H.ok(pdf, "export yields a path: " .. tostring(pdf_err))
  H.ok(pdf ~= nil and vim.uv.fs_stat(pdf) ~= nil, "…and the file really exists")
  H.contains(pdf or "", ".pdf", "…with a .pdf extension")
  H.eq(vim.fn.fnamemodify(pdf or "", ":r"), vim.fn.fnamemodify(png or "", ":r"), "…same stem as the source file")

  -- ── redact: missing file ─────────────────────────────────────────────────
  local redacted, redact_err = convert.redact("/definitely/does/not/exist.png", { { x1 = 0, y1 = 0, x2 = 5, y2 = 5 } })
  H.falsy(redacted, "a missing file yields no result")
  H.contains(redact_err or "", "not found", "…but a reason")

  -- ── redact: no box ───────────────────────────────────────────────────────
  redacted, redact_err = convert.redact(assert(png), {})
  H.falsy(redacted, "without a box there is nothing to redact")
  H.contains(redact_err or "", "box", "…with an explanatory message")

  -- ── redact: real redaction ───────────────────────────────────────────────
  redacted, redact_err = convert.redact(assert(png), { { x1 = 0, y1 = 0, x2 = 5, y2 = 5 } })
  H.ok(redacted, "redaction yields a path: " .. tostring(redact_err))
  H.ok(redacted ~= nil and vim.uv.fs_stat(redacted) ~= nil, "…and the file really exists")
  H.contains(redacted or "", ".redacted.png", "…named .redacted.<extension>")
  H.ok(redacted ~= png, "…as its own file, not overwriting the original")
  H.ok(vim.uv.fs_stat(png) ~= nil, "…the original stays untouched")
end
