-- TESTS/ocr_spec.lua — reading text out of an image via tesseract.
--
-- Two halves. `to_lines` and the binary resolution are checkable anywhere:
-- the first is pure, the second only reads configuration and the filesystem.
-- The recognition itself needs both tesseract AND ImageMagick — the latter to
-- *make* an image with known text in it, so the assertion can be "the words
-- come back" rather than "something came back". Without either, that half is
-- skipped rather than failed, the same stance convert_spec takes.

---@param H table harness from TESTS/run.lua
return function(H)
  local ocr = require("images.ocr")
  local config = require("images.config")

  -- ── to_lines ─────────────────────────────────────────────────────────────
  H.eq(#ocr.to_lines(""), 0, "empty text yields no lines")

  local lines = ocr.to_lines("hello   \nworld\t\n")
  H.eq(#lines, 2, "trailing whitespace does not create lines")
  H.eq(lines[1], "hello", "trailing spaces are stripped")
  H.eq(lines[2], "world", "…tabs too")

  lines = ocr.to_lines("a\n\n\n\nb")
  H.eq(#lines, 3, "a run of blank lines collapses to one")
  H.eq(lines[2], "", "…and that one is kept, so paragraphs survive")

  lines = ocr.to_lines("\n\n\nfirst\nsecond\n\n\n")
  H.eq(lines[1], "first", "leading blank lines are dropped entirely")
  H.eq(#lines, 2, "…as are trailing ones")

  -- ── bin(): the configured path wins, without a stat ───────────────────────
  -- `/nope/tesseract` deliberately does not exist: an explicit setting is a
  -- decision, and this asserts the module does not quietly overrule it.
  local saved = config.get().ocr.bin
  config.setup({ ocr = { bin = "/nope/tesseract" } })
  ocr.clear()
  H.eq(ocr.bin(), "/nope/tesseract", "a configured bin is used as given")
  H.ok(ocr.available(), "…and counts as available, however implausible")

  config.setup({ ocr = { bin = saved } })
  ocr.clear()

  -- Without a configured path the answer is a string or nil, never a stray
  -- `false` leaking out of the memo.
  local found = ocr.bin()
  H.ok(found == nil or type(found) == "string", "bin() is a path or nil, never false")
  H.eq(ocr.available(), found ~= nil, "available() agrees with bin()")

  -- ── run: waits for the result, never for a fixed interval ────────────────
  ---@param start fun(cb: function)
  ---@return any, any, boolean fired
  local function await(start)
    local fired, a, b = false, nil, nil
    start(function(x, y)
      a, b, fired = x, y, true
    end)
    vim.wait(30000, function()
      return fired
    end, 20)
    return a, b, fired
  end

  -- ── run: missing file ────────────────────────────────────────────────────
  -- Only meaningful with tesseract present: without it the earlier "no
  -- tesseract" guard fires first, which is the correct order but a different
  -- message.
  if not ocr.available() then
    return
  end

  local text, err, fired = await(function(cb)
    ocr.run("/definitely/does/not/exist.png", nil, cb)
  end)
  H.ok(fired, "a missing file still calls back")
  H.falsy(text, "…with no text")
  H.contains(err or "", "not found", "…but a reason")

  -- ── run: an unknown language reports what IS installed ───────────────────
  H.ok(#ocr.languages() > 0, "tesseract reports at least one installed language")

  if vim.fn.executable("magick") == 0 then
    -- No way to produce an image with known text in it, so the recognition
    -- itself cannot be asserted on -- only guessed at, which is worse than
    -- skipping.
    return
  end

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local img = root .. "/ocr.png"

  -- Large, black on white, one short uppercase word: the point is to assert
  -- that the pipeline delivers recognised text, not to benchmark tesseract on
  -- a hard sample. A small or noisy image would make this spec flaky for
  -- reasons that have nothing to do with the code under test.
  local made = vim
    .system({
      "magick",
      "-size",
      "600x160",
      "xc:white",
      "-pointsize",
      "72",
      "-fill",
      "black",
      "-annotate",
      "+30+100",
      "NEOVIM",
      img,
    }, { text = true })
    :wait()
  if made.code ~= 0 or not vim.uv.fs_stat(img) then
    -- ImageMagick without a usable font cannot render the sample; that is a
    -- property of the machine, not a failure of this module.
    return
  end

  text, err, fired = await(function(cb)
    ocr.run(img, { lang = "eng" }, cb)
  end)
  H.ok(fired, "recognition calls back")
  H.ok(text ~= nil, "…with text: " .. tostring(err))
  H.contains((text or ""):upper(), "NEOVIM", "…and the word in the image is in it")

  -- ── run: a language that is not installed ────────────────────────────────
  -- "zzz" is not a tesseract language code and never will be, so this asserts
  -- the translated error rather than tesseract's own wording.
  text, err = await(function(cb)
    ocr.run(img, { lang = "zzz" }, cb)
  end)
  H.falsy(text, "an unknown language yields no text")
  H.contains(err or "", "zzz", "…and the error names the language asked for")
  H.contains(err or "", "available", "…plus what is installed instead")
end
