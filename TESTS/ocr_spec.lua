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

  -- ── upscale_factor: what `ocr.upscale` means ──────────────────────────────
  H.eq(ocr.upscale_factor(true), 2, "upscale = true means the measured 2x")
  H.eq(ocr.upscale_factor(3), 3, "a number above 1 is the factor itself")
  H.eq(ocr.upscale_factor(1.5), 1.5, "…fractions included")
  H.eq(ocr.upscale_factor(false), nil, "false is off")
  H.eq(ocr.upscale_factor(nil), nil, "nil is off")
  H.eq(ocr.upscale_factor(1), nil, "1 is off: nothing to enlarge")
  H.eq(ocr.upscale_factor(0.5), nil, "a shrinking factor is off, never passed on")
  H.eq(ocr.upscale_factor("2"), nil, "a string is off")
  H.eq(ocr.upscale_factor(8), 8, "the cap itself is accepted")
  local f200, why200 = ocr.upscale_factor(200)
  H.eq(f200, nil, "200 (a percentage) is rejected")
  H.contains(why200 or "", "percentage", "…with a reason")
  H.eq(ocr.upscale_factor(math.huge), nil, "math.huge is rejected")
  H.eq(ocr.upscale_factor(0 / 0), nil, "NaN is off")

  -- ── health: ocr.upscale is reported next to the other OCR dependencies ───
  do
    local exe = require("lib.nvim.cross.executable")
    local real_exists, real_health = exe.exists, vim.health
    local saved_cfg = vim.deepcopy(config.get().ocr)
    local seen, has_magick = {}, true
    ---@diagnostic disable-next-line: duplicate-set-field
    exe.exists = function(name)
      if name == "magick" then return has_magick end
      return real_exists(name)
    end
    local function spy(level)
      return function(msg)
        seen[#seen + 1] = level .. ": " .. tostring(msg)
      end
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.health = { ok = spy("ok"), warn = spy("warn"), info = spy("info"), error = spy("error") }
    local function check(upscale, magick)
      seen, has_magick = {}, magick
      config.setup({ ocr = { upscale = upscale } })
      require("images.health").check_ocr_upscale()
      return table.concat(seen, "\n")
    end
    local ok_h, h_err = pcall(function()
      H.eq(check(false, false), "", "health: upscale off says nothing")
      H.contains(check(true, false), "warn: `ocr.upscale` is set but `magick` is missing", "health: warns without magick")
      H.contains(check(true, true), "ok: ", "health: ok with magick")
      H.contains(check(200, true), "warn: ", "health: warns about a percentage")
    end)
    vim.health, exe.exists = real_health, real_exists
    config.setup({ ocr = saved_cfg })
    if not ok_h then error(h_err, 0) end
  end

  -- ── run with upscale: the pipeline, with both processes stubbed ───────────
  -- Neither tesseract nor ImageMagick is needed here (CI has neither): the
  -- point is which argv reaches which process, which file tesseract reads,
  -- that the temporary copy is gone afterwards, and the fallback notice.
  do
    local exe = require("lib.nvim.cross.executable")
    local real_system, real_exists = vim.system, exe.exists
    local saved_ocr = vim.deepcopy(config.get().ocr)

    local input = vim.fn.tempname() .. ".png"
    H.write(input, "not really a png; the processes are stubbed")

    local calls, magick_fails, magick_present = {}, false, true
    ---@diagnostic disable-next-line: duplicate-set-field
    exe.exists = function(name)
      if name == "magick" then return magick_present end
      return real_exists(name)
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(argv, _, on_exit)
      calls[#calls + 1] = vim.deepcopy(argv)
      local result
      if argv[1] == "magick" then
        if magick_fails then
          -- magick may leave a half-written output behind and still fail.
          H.write(argv[#argv], "partial")
          result = { code = 1, stdout = "", stderr = "magick: boom" }
        elseif not argv[2]:find("%[0%]$") then
          -- Like the real magick on a multi-frame input (animated GIF/WebP)
          -- without a frame selector: numbered files, exit 0, no `out`.
          local stem = argv[#argv]:gsub("%.png$", "")
          H.write(stem .. "-0.png", "frame 0")
          H.write(stem .. "-1.png", "frame 1")
          result = { code = 0, stdout = "", stderr = "" }
        else
          H.write(argv[#argv], "enlarged")
          result = { code = 0, stdout = "", stderr = "" }
        end
      else
        result = { code = 0, stdout = "READ FROM " .. argv[2] .. "\n", stderr = "" }
      end
      on_exit(result)
      return {
        wait = function()
          return result
        end,
      }
    end

    local function reset(upscale)
      calls, magick_fails, magick_present = {}, false, true
      config.setup({ ocr = { bin = "/fake/tesseract", upscale = upscale } })
      ocr.clear()
    end

    local ok_run, run_err = pcall(function()
      -- Off by default: tesseract reads the original, magick never runs.
      reset(nil)
      H.eq(config.get().ocr.upscale, false, "ocr.upscale defaults to off")
      local text, err, fired, notice
      local function go(opts)
        fired, text, err, notice = false, nil, nil, nil
        ocr.run(input, opts, function(t, e, n)
          text, err, notice, fired = t, e, n, true
        end)
        vim.wait(5000, function()
          return fired
        end, 10)
      end

      go(nil)
      H.ok(fired, "default run calls back")
      H.eq(#calls, 1, "default: one process only (tesseract)")
      H.eq(calls[1][2], input, "default: tesseract reads the original")
      H.eq(notice, nil, "default: no notice")

      -- upscale = true: magick -resize 200% into a temp copy, tesseract on it.
      reset(true)
      go(nil)
      H.eq(#calls, 2, "upscale: magick, then tesseract")
      H.eq(calls[1][1], "magick", "upscale: magick runs first")
      H.eq(calls[1][2], input .. "[0]", "…on the original's first frame only")
      H.eq(calls[1][3], "-resize", "…with -resize")
      H.eq(calls[1][4], "200%", "…by 200% for upscale = true")
      local copy = calls[1][5]
      H.eq(calls[2][2], copy, "tesseract reads the enlarged copy")
      H.ok(copy ~= input, "…which is not the original")
      H.falsy(vim.uv.fs_stat(copy), "the enlarged copy is deleted afterwards")
      H.ok(vim.uv.fs_stat(input) ~= nil, "…the original is left alone")
      H.contains(text or "", copy, "the text comes from the enlarged read")
      H.eq(err, nil, "upscale: no error")
      H.eq(notice, nil, "upscale: no notice when it worked")
      local stem = copy:gsub("%.png$", "")
      H.falsy(vim.uv.fs_stat(stem .. "-0.png"), "no numbered per-frame copies are left behind")

      -- opts.upscale overrides the configuration, both ways.
      reset(false)
      go({ upscale = 1.5 })
      H.eq(calls[1][4], "150%", "opts.upscale = 1.5 resizes by 150%")
      reset(true)
      go({ upscale = false })
      H.eq(#calls, 1, "opts.upscale = false switches a configured upscale off")

      -- No ImageMagick: the original is read, with a notice, not an error.
      reset(true)
      magick_present = false
      go(nil)
      H.eq(#calls, 1, "without magick only tesseract runs")
      H.eq(calls[1][2], input, "…on the original")
      H.ok(text ~= nil, "…and the text still arrives")
      H.eq(err, nil, "…with no error")
      H.contains(notice or "", "magick", "…but a notice naming the missing tool")

      -- magick fails: same fallback, the notice carries its stderr.
      reset(true)
      magick_fails = true
      go(nil)
      H.eq(#calls, 2, "a failing magick still lets tesseract run")
      H.eq(calls[2][2], input, "…on the original")
      H.ok(text ~= nil, "…and the text arrives")
      H.contains(notice or "", "boom", "…with magick's own error in the notice")
      H.falsy(vim.uv.fs_stat(calls[1][5]), "a failed upscale leaves no temp file")

      -- A percentage where a factor belongs: no magick run, a notice instead.
      for _, typo in ipairs({ 200, math.huge }) do
        reset(typo)
        go(nil)
        H.ok(fired, ("upscale = %s still calls back"):format(tostring(typo)))
        H.eq(#calls, 1, ("upscale = %s: magick never runs"):format(tostring(typo)))
        H.eq(calls[1][2], input, "…tesseract reads the original")
        H.eq(err, nil, "…with no error")
        H.contains(notice or "", "percentage", "…but a notice about the implausible factor")
      end
    end)

    vim.system, exe.exists = real_system, real_exists
    config.setup({ ocr = saved_ocr })
    ocr.clear()
    os.remove(input)
    if not ok_run then error(run_err, 0) end
  end

  -- ── run: missing file ────────────────────────────────────────────────────
  -- Only meaningful with tesseract present: without it the earlier "no
  -- tesseract" guard fires first, which is the correct order but a different
  -- message.
  if not ocr.available() then
    print("n/a  the OCR run checks need tesseract")
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

  -- The same image through the real `magick -resize` first.
  local notice
  text, err, fired = await(function(cb)
    ocr.run(img, { lang = "eng", upscale = true }, function(t, e, n)
      notice = n
      cb(t, e)
    end)
  end)
  H.ok(fired, "upscaled recognition calls back")
  H.eq(notice, nil, "…without a fallback notice: " .. tostring(notice))
  H.contains((text or ""):upper(), "NEOVIM", "…and still reads the word: " .. tostring(err))

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
