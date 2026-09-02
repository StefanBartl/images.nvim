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
  fd:write('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">' .. '<rect width="10" height="10" fill="red"/></svg>')
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

  -- `to_pdf` and `redact` are asynchronous: both hand their result to
  -- `on_done` and their return values are nil on every path that actually
  -- starts a conversion. Asserting on the return value tested nil against nil
  -- and reported "export yields a path: nil".
  --
  -- Waits for the *result*, never a fixed sleep -- a `vim.wait(200)` after an
  -- async call is a coin flip on a loaded machine. The callback may also fire
  -- synchronously (the early-return failures do), which `vim.wait` handles
  -- because it evaluates the predicate before the first sleep.
  ---@param start fun(cb: function)
  ---@return any, any, boolean fired
  local function await(start)
    local fired, a, b = false, nil, nil
    start(function(x, y)
      a, b, fired = x, y, true
    end)
    vim.wait(20000, function()
      return fired
    end, 20)
    return a, b, fired
  end

  -- ── to_pdf: missing file ─────────────────────────────────────────────────
  -- The one case that also reports synchronously, because it fails before
  -- starting -- so both routes are asserted.
  local pdf, pdf_err = convert.to_pdf("/definitely/does/not/exist.png")
  H.falsy(pdf, "a missing file yields no PDF")
  H.contains(pdf_err or "", "not found", "…but a reason")

  local pdf_ok, pdf_msg, fired = await(function(cb)
    convert.to_pdf("/definitely/does/not/exist.png", cb)
  end)
  H.ok(fired, "…and on_done still fires for a pre-start failure")
  H.falsy(pdf_ok, "…reporting failure")
  H.contains(pdf_msg or "", "not found", "…with the same reason")

  -- ── to_pdf: real conversion ──────────────────────────────────────────────
  -- Callback shape here is (ok, out_path_or_err) -- note it differs from
  -- `redact`'s (out_path, err) below.
  local ok_pdf, pdf_path
  ok_pdf, pdf_path, fired = await(function(cb)
    convert.to_pdf(assert(png), cb)
  end)
  H.ok(fired, "export calls back")
  H.ok(ok_pdf, "export succeeds: " .. tostring(pdf_path))
  H.ok(pdf_path ~= nil and vim.uv.fs_stat(pdf_path) ~= nil, "…and the file really exists")
  H.contains(pdf_path or "", ".pdf", "…with a .pdf extension")
  H.eq(vim.fn.fnamemodify(pdf_path or "", ":r"), vim.fn.fnamemodify(png or "", ":r"), "…same stem as the source file")

  -- ── redact: missing file ─────────────────────────────────────────────────
  -- `redact` returns nothing at all, on any path, so every case goes through
  -- the callback.
  local redacted, redact_err
  redacted, redact_err = await(function(cb)
    convert.redact("/definitely/does/not/exist.png", { { x1 = 0, y1 = 0, x2 = 5, y2 = 5 } }, cb)
  end)
  H.falsy(redacted, "a missing file yields no result")
  H.contains(redact_err or "", "not found", "…but a reason")

  -- ── redact: no box ───────────────────────────────────────────────────────
  redacted, redact_err = await(function(cb)
    convert.redact(assert(png), {}, cb)
  end)
  H.falsy(redacted, "without a box there is nothing to redact")
  H.contains(redact_err or "", "box", "…with an explanatory message")

  -- ── redact: real redaction ───────────────────────────────────────────────
  redacted, redact_err, fired = await(function(cb)
    convert.redact(assert(png), { { x1 = 0, y1 = 0, x2 = 5, y2 = 5 } }, cb)
  end)
  H.ok(fired, "redaction calls back")
  H.ok(redacted, "redaction yields a path: " .. tostring(redact_err))
  H.ok(redacted ~= nil and vim.uv.fs_stat(redacted) ~= nil, "…and the file really exists")
  H.contains(redacted or "", ".redacted.png", "…named .redacted.<extension>")
  H.ok(redacted ~= png, "…as its own file, not overwriting the original")
  H.ok(vim.uv.fs_stat(assert(png)) ~= nil, "…the original stays untouched")

  -- == Image operations as file operations ==================================

  -- ── valid_geometry: pure, so it runs before anything touches disk ────────
  for _, good in ipairs({ "50%", "800x600", "800x600!", "800x", "x600", "800" }) do
    H.ok(convert.valid_geometry(good), ("%q is a size"):format(good))
  end
  for _, bad in ipairs({ "", "big", "50 %", "800*600", "x", "-5", "800x600px", "%50" }) do
    H.falsy(convert.valid_geometry(bad), ("%q is not a size"):format(bad))
  end
  H.falsy(convert.valid_geometry(nil), "nil is not a size")

  -- ── valid_crop: pure, and deliberately stricter than valid_geometry ──────
  -- `magick -crop 800x600` without an offset is a *tiling* operation and
  -- yields many images; a caller asking for "this rectangle" never means that,
  -- and letting it through would write a file with a surprising number in its
  -- name rather than fail.
  for _, good in ipairs({ "800x600+0+0", "1x1+0+0", "960x540+480+270", "10x10-5-5" }) do
    H.ok(convert.valid_crop(good), ("%q is a rectangle"):format(good))
  end
  for _, bad in ipairs({ "", "800x600", "50%", "+10+20", "800x600+10", "800x600+10+20+30", "axb+0+0" }) do
    H.falsy(convert.valid_crop(bad), ("%q is not a rectangle"):format(bad))
  end
  H.falsy(convert.valid_crop(nil), "nil is not a rectangle")

  -- ── crop: bad input never reaches magick ─────────────────────────────────
  local cropped, crop_err = await(function(cb)
    convert.crop(assert(png), "not-a-rect", root .. "/c1.png", nil, cb)
  end)
  H.falsy(cropped, "a bad rectangle yields no file")
  H.contains(crop_err or "", "not a rectangle", "…and says so before magick is ever run")

  cropped, crop_err = await(function(cb)
    convert.crop(assert(png), "5x5+0+0", root .. "/c2.png", { fit = "not-a-size" }, cb)
  end)
  H.falsy(cropped, "a bad fit geometry yields no file either")
  H.contains(crop_err or "", "not a size", "…named as the size it is not")

  cropped, crop_err = await(function(cb)
    convert.crop(assert(png), "5x5+0+0", "", nil, cb)
  end)
  H.falsy(cropped, "no destination yields no file")
  H.contains(crop_err or "", "destination", "…and says which half is missing")

  -- ── crop: real, into a destination the caller names ──────────────────────
  -- The point of the caller naming it: a crop is a draw path, not an export,
  -- so the file belongs in the caller's own cache rather than beside a
  -- customer's attachment.
  local dest = root .. "/crops/detail.png"
  cropped, crop_err, fired = await(function(cb)
    convert.crop(assert(png), "5x5+0+0", dest, nil, cb)
  end)
  H.ok(fired, "crop calls back")
  H.ok(cropped, "crop yields a path: " .. tostring(crop_err))
  H.ok(cropped == dest, "…exactly the destination that was asked for")
  H.ok(cropped ~= nil and vim.uv.fs_stat(cropped) ~= nil, "…and the file really exists")
  H.ok(vim.uv.fs_stat(assert(png)) ~= nil, "…the original stays untouched")

  local dims = require("images.info").collect(assert(cropped))
  H.ok(dims ~= nil and dims.width == 5 and dims.height == 5, "…and it is the rectangle asked for")

  -- ── crop: `fit` runs in the same process as the crop ─────────────────────
  -- Two `magick` calls would be two process starts, measured at ~71 ms each
  -- on this machine against a total of ~250 ms. Worth one argument.
  local fitted = select(1, await(function(cb)
    convert.crop(assert(png), "8x8+0+0", root .. "/crops/fitted.png", { fit = "4x4!" }, cb)
  end))
  H.ok(fitted, "crop with a fit yields a path")
  local fdims = fitted and require("images.info").collect(fitted) or nil
  H.ok(fdims ~= nil and fdims.width == 4 and fdims.height == 4, "…cropped, then resized, in one run")

  -- ── target_formats ───────────────────────────────────────────────────────
  local formats = convert.target_formats()
  H.ok(vim.tbl_contains(formats, "png"), "png is a target format")
  H.ok(vim.tbl_contains(formats, "pdf"), "…and pdf, which no `extensions` entry supplies")
  H.falsy(vim.tbl_contains(formats, "svg"), "…but not svg: rasterising into an SVG wrapper is not a conversion")

  -- ── resize: a bad geometry never reaches magick ──────────────────────────
  -- The point of validating in Lua: `magick` treats an unparseable geometry as
  -- "no geometry" and exits 0, so without this the result would be a
  -- `.scaled.` copy at the original size.
  local scaled, scale_err = await(function(cb)
    convert.resize(assert(png), "not-a-size", cb)
  end)
  H.falsy(scaled, "a bad geometry yields no file")
  H.contains(scale_err or "", "not a size", "…and says so before magick is ever run")

  -- ── resize: real ─────────────────────────────────────────────────────────
  scaled, scale_err, fired = await(function(cb)
    convert.resize(assert(png), "50%", cb)
  end)
  H.ok(fired, "resize calls back")
  H.ok(scaled, "resize yields a path: " .. tostring(scale_err))
  H.ok(scaled ~= nil and vim.uv.fs_stat(scaled) ~= nil, "…and the file really exists")
  H.contains(scaled or "", ".scaled.png", "…named .scaled.<extension>")
  H.ok(vim.uv.fs_stat(assert(png)) ~= nil, "…the original stays untouched")

  -- The resized file is genuinely smaller in pixels, not merely a copy — the
  -- assertion the exit code alone would not give.
  local info = require("images.info")
  local before_dim = info.collect(assert(png))
  local after_dim = info.collect(assert(scaled))
  if before_dim and after_dim and before_dim.width and after_dim.width then
    H.ok(after_dim.width < before_dim.width, "…and it really is narrower than the source")
  end

  -- ── optimise: an out-of-range quality is refused before magick ───────────
  local opt, opt_err = await(function(cb)
    convert.optimise(assert(png), { quality = 150 }, cb)
  end)
  H.falsy(opt, "quality 150 yields no file")
  H.contains(opt_err or "", "between 1 and 100", "…with the range in the message")

  -- ── optimise: missing file ───────────────────────────────────────────────
  opt, opt_err = await(function(cb)
    convert.optimise("/definitely/does/not/exist.png", nil, cb)
  end)
  H.falsy(opt, "a missing file yields no result")
  H.contains(opt_err or "", "not found", "…but a reason")

  -- ── optimise: real ───────────────────────────────────────────────────────
  -- Both outcomes are correct here: a 10x10 red square converted from SVG has
  -- essentially nothing to strip, so "already optimal" is the likely answer
  -- and is asserted as a success, not a failure. What must hold either way is
  -- that there is no error and that the sizes are reported.
  local out_path, err_opt, before_bytes, after_bytes
  local fired_opt = false
  convert.optimise(assert(png), nil, function(o, e, b, a)
    out_path, err_opt, before_bytes, after_bytes, fired_opt = o, e, b, a, true
  end)
  vim.wait(20000, function()
    return fired_opt
  end, 20)
  H.ok(fired_opt, "optimise calls back")
  H.falsy(err_opt, "…without an error: " .. tostring(err_opt))
  H.ok(type(before_bytes) == "number" and before_bytes > 0, "…reporting the source size")
  H.ok(type(after_bytes) == "number", "…and the size it managed")
  if out_path then
    H.contains(out_path, ".optimised.png", "a written result is named .optimised.<extension>")
    H.ok(after_bytes < before_bytes, "…and is genuinely smaller")
  else
    H.ok(after_bytes >= before_bytes, "no result means it could not get smaller")
    H.falsy(
      vim.uv.fs_stat(vim.fn.fnamemodify(assert(png), ":r") .. ".optimised.png"),
      "…and the larger attempt was deleted rather than left behind"
    )
  end

  -- ── to_format: refuses to rewrite the source in place ────────────────────
  local conv, conv_err = await(function(cb)
    convert.to_format(assert(png), "png", cb)
  end)
  H.falsy(conv, "converting a png to png yields no file")
  H.contains(conv_err or "", "already", "…because that would be an in-place edit")
  H.ok(vim.uv.fs_stat(assert(png)) ~= nil, "…and the source is still there")

  -- ── to_format: real ──────────────────────────────────────────────────────
  conv, conv_err, fired = await(function(cb)
    convert.to_format(assert(png), "jpg", cb)
  end)
  H.ok(fired, "conversion calls back")
  H.ok(conv, "conversion yields a path: " .. tostring(conv_err))
  H.ok(conv ~= nil and vim.uv.fs_stat(conv) ~= nil, "…and the file really exists")
  H.contains(conv or "", ".jpg", "…with the requested extension")
  H.eq(vim.fn.fnamemodify(conv or "", ":r"), vim.fn.fnamemodify(png or "", ":r"), "…on the same stem as the source")

  -- ── to_format: pdf takes the export route ────────────────────────────────
  -- Same result as `to_pdf`, reached through the other name — the point being
  -- that there is one PDF path, not two that could drift.
  conv, conv_err = await(function(cb)
    convert.to_format(assert(png), "pdf", cb)
  end)
  H.ok(conv, "pdf as a target yields a path: " .. tostring(conv_err))
  H.contains(conv or "", ".pdf", "…a PDF")
end
