-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a generated fixture, a sampled payload -- this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/blocks_spec.lua — images.blocks: the argv it builds, the payload it
-- validates, and the two properties the whole approach rests on — that
-- painting a frame touches only highlights, and that the number of highlight
-- groups it can ever create is bounded.
--
-- The bound is the point. Neovim stops at 19 602 highlight groups (measured
-- 2026-09-08) and never frees one, so an unquantised cell grid is not a
-- prettier renderer with a caveat — it is one that ends a session's colouring.

return function(H)
  local eq = H.eq
  local ok = H.ok
  local falsy = H.falsy
  local blocks = require("images.blocks")

  --- Run `fn` with a given cell geometry configured, and put back whatever was
  --- configured before.
  ---
  --- Explicit rather than implicit throughout this spec: half blocks and
  --- sextants differ in what a payload has to be and in whether the buffer
  --- text changes between frames, so a test that does not say which one it
  --- means is a test that passes for the wrong reason when the default moves.
  ---@param name string
  ---@param fn fun(): nil
  local function with_cells(name, fn)
    local config = require("images.config")
    local saved = ((config.get().display or {}).ascii_fallback or {}).cells
    config.setup({ display = { ascii_fallback = { cells = name } } })
    local ok_run, err = pcall(fn)
    config.setup({ display = { ascii_fallback = { cells = saved } } })
    if not ok_run then error(err, 0) end
  end

  -- ---------- argv ----------

  do
    local argv = blocks.sample_argv({ "/a.png", "/b.png" }, 40, 20, blocks.GEOMETRIES.half)
    eq(argv[1], "magick", "sample_argv: the binary")
    eq(argv[2], "/a.png[0]", "sample_argv: first frame of every input")
    eq(argv[3], "/b.png[0]", "sample_argv: every path is passed to one process")
    local joined = table.concat(argv, " ")
    -- Twice the rows in pixels: one text row is two pixel rows (half block).
    ok(joined:find("-resize 40x40!", 1, true) ~= nil, "sample_argv: the pixel grid is twice as tall as the cell grid")
    ok(joined:find("-alpha off", 1, true) ~= nil, "sample_argv: no alpha, so 3 bytes per pixel")
    eq(argv[#argv], "RGB:-", "sample_argv: raw bytes on stdout")

    eq(
      blocks.frame_bytes(40, 20, blocks.GEOMETRIES.half),
      40 * 20 * 2 * 3,
      "frame_bytes: three bytes per pixel, two pixels per cell"
    )
  end

  -- ---------- geometry ----------

  -- **The grid a geometry asks ImageMagick for, and the payload it implies.**
  -- These two have to agree exactly: a resize that produces fewer pixels than
  -- `frame_bytes` expects makes every read short, and one that produces more
  -- silently shifts every row of the picture. Neither raises anything.
  do
    for _, case in ipairs({
      { name = "half", cols = 1, rows = 2 },
      { name = "quadrant", cols = 2, rows = 2 },
      { name = "sextant", cols = 2, rows = 3 },
    }) do
      local geo = blocks.GEOMETRIES[case.name]
      ok(geo ~= nil, "geometry: " .. case.name .. " exists")
      eq(geo.cols, case.cols, "geometry: " .. case.name .. " sub-pixel columns")
      eq(geo.rows, case.rows, "geometry: " .. case.name .. " sub-pixel rows")

      local joined = table.concat(blocks.sample_argv({ "/a.png" }, 40, 20, geo), " ")
      local want = ("-resize %dx%d!"):format(40 * geo.cols, 20 * geo.rows)
      ok(joined:find(want, 1, true) ~= nil, "geometry: " .. case.name .. " asks for " .. want)
      eq(
        blocks.frame_bytes(40, 20, geo),
        40 * geo.cols * 20 * geo.rows * 3,
        "geometry: " .. case.name .. " payload matches the grid it asked for"
      )

      if geo.chars then
        eq(#geo.chars, 2 ^ (geo.cols * geo.rows), "geometry: " .. case.name .. " has a character per pattern")
        for i, char in ipairs(geo.chars) do
          ok(type(char) == "string" and #char > 0, ("geometry: %s pattern %d has a character"):format(case.name, i - 1))
        end
      end
    end

    -- The four patterns Unicode did *not* put in the sextant block, because
    -- characters for them already existed. An off-by-one in the mapping walks
    -- the whole table along and is invisible except as a wrong picture -- and
    -- 21 and 42 are the vertical edges, the most common pattern there is.
    local sx = blocks.GEOMETRIES.sextant.chars
    eq(sx[21 + 1], "▌", "sextant: pattern 21 is the left half block")
    eq(sx[42 + 1], "▐", "sextant: pattern 42 is the right half block")
    eq(sx[63 + 1], "█", "sextant: everything set is the full block")
    eq(sx[1 + 1], vim.fn.nr2char(0x1FB00), "sextant: pattern 1 is the first character of the block")
    eq(sx[2 + 1], vim.fn.nr2char(0x1FB01), "sextant: pattern 2 is the second")
    -- Right after the first skipped one, which is where an off-by-one shows.
    eq(sx[22 + 1], vim.fn.nr2char(0x1FB14), "sextant: pattern 22 accounts for the skipped 21")
    eq(sx[43 + 1], vim.fn.nr2char(0x1FB28), "sextant: pattern 43 accounts for both skips")
  end

  -- ---------- painting with a finer geometry ----------

  -- A geometry finer than a half block has to *choose* a character per cell,
  -- so unlike the half block it rewrites the line. What must not change is
  -- everything around that: the line count, the cell count per line, and the
  -- buffer staying unmodifiable afterwards.
  do
    local saved = require("images.config").get().display.ascii_fallback.cells
    require("images.config").setup({ display = { ascii_fallback = { cells = "sextant" } } })

    local cols, rows = 6, 3
    local geo = blocks.GEOMETRIES.sextant
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))
    vim.bo[buf].modifiable = false
    local ns = vim.api.nvim_create_namespace("blocks_spec_sextant")

    -- A gradient, so cells actually differ and patterns are not all zero.
    local parts = {}
    for i = 1, blocks.frame_bytes(cols, rows, geo) / 3 do
      local v = (i * 7) % 256
      parts[#parts + 1] = string.char(v, 255 - v, (v * 3) % 256)
    end
    local raw = table.concat(parts)

    local painted, err = blocks.paint(buf, ns, raw, 1, cols, rows)
    ok(painted, "sextant paint: draws (" .. tostring(err) .. ")")

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(#lines, rows, "sextant paint: the canvas keeps its line count")
    for i, line in ipairs(lines) do
      eq(vim.fn.strchars(line), cols, "sextant paint: line " .. i .. " keeps its cell count")
    end
    ok(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0, "sextant paint: highlights the cells it wrote")
    falsy(vim.bo[buf].modifiable, "sextant paint: leaves the buffer as it found it")

    -- Highlight columns are byte columns, and a sextant is four bytes while
    -- the half blocks it borrows are three -- so a mark's end must land on a
    -- real character boundary, never inside one.
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      local row, col, details = mark[2], mark[3], mark[4]
      local line = lines[row + 1]
      ok(
        col == 0 or col == #line or vim.fn.byteidx(line, vim.fn.charidx(line, col)) == col,
        "sextant paint: extmark starts on a character boundary"
      )
      local stop = details and details.end_col or nil
      if stop then
        ok(
          stop == #line or vim.fn.byteidx(line, vim.fn.charidx(line, stop)) == stop,
          "sextant paint: extmark ends on a character boundary"
        )
      end
    end

    vim.api.nvim_buf_delete(buf, { force = true })
    require("images.config").setup({ display = { ascii_fallback = { cells = saved } } })
  end

  -- ---------- payload validation ----------

  do
    local raw, err = blocks.read_sampled({ code = 1, stderr = "boom" }, 1, 4, 4, blocks.GEOMETRIES.half)
    eq(raw, nil, "read_sampled: nothing on a failed process")
    ok(err and err:find("boom", 1, true) ~= nil, "read_sampled: reports what magick said")

    -- The failure that matters: the process succeeded but wrote a short
    -- payload. Silently accepting it paints the previous frame's leftovers.
    raw, err = blocks.read_sampled({ code = 0, stdout = ("x"):rep(10) }, 1, 4, 4, blocks.GEOMETRIES.half)
    eq(raw, nil, "read_sampled: a short payload is an error, not a partial frame")
    ok(err and err:find("of 96 bytes", 1, true) ~= nil, "read_sampled: says how short")

    local full = ("x"):rep(96)
    raw, err = blocks.read_sampled({ code = 0, stdout = full }, 1, 4, 4, blocks.GEOMETRIES.half)
    eq(raw, full, "read_sampled: passes a complete payload through")
    eq(err, nil, "read_sampled: no error alongside a payload")
  end

  -- ---------- canvas ----------

  do
    -- The shape holds for every geometry: one line per row, one character per
    -- column. Only the half block promises *which* character, because it is
    -- the one geometry whose text never changes afterwards.
    for _, name in ipairs({ "half", "quadrant", "sextant" }) do
      with_cells(name, function()
        local lines = blocks.canvas_lines(5, 3)
        eq(#lines, 3, "canvas_lines: one line per row (" .. name .. ")")
        eq(vim.fn.strchars(lines[1]), 5, "canvas_lines: one cell character per column (" .. name .. ")")
      end)
    end
    with_cells("half", function()
      eq(blocks.canvas_lines(5, 3)[1], blocks.BLOCK:rep(5), "canvas_lines: half blocks all the way across")
    end)
  end

  -- ---------- paint (half blocks: the text never changes) ----------

  with_cells("half", function()
    local cols, rows = 4, 2
    local ns = vim.api.nvim_create_namespace("blocks_spec")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))

    -- Two frames: the first all one colour, the second a different one.
    -- `frame_bytes`, not a sub-pixel count of the spec's own: a cell holds
    -- two sub-pixels with half blocks and six with sextants, and a payload
    -- sized for the wrong one is short -- which paints the previous frame's
    -- leftovers rather than failing.
    local pixels = blocks.frame_bytes(cols, rows) / 3
    local frame_a = string.char(255, 0, 0):rep(pixels)
    local frame_b = string.char(0, 0, 255):rep(pixels)
    local raw = frame_a .. frame_b

    local painted, err = blocks.paint(buf, ns, raw, 1, cols, rows)
    ok(painted, "paint: draws frame 1 (" .. tostring(err) .. ")")

    -- Joined, not the table: `eq` compares tables by identity.
    local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    -- One run per row: a flat frame collapses to `rows` extmarks, not
    -- `cols * rows`. This is what makes flat material cheap.
    eq(#marks, rows, "paint: adjacent cells of one colour share an extmark")

    ok(blocks.paint(buf, ns, raw, 2, cols, rows), "paint: draws frame 2")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|"),
      before,
      "paint: a new frame changes highlights only, never the buffer text"
    )
    eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), rows, "paint: the previous frame's marks are gone")

    -- Past the end is an error, not a wrapped frame.
    local past, past_err = blocks.paint(buf, ns, raw, 3, cols, rows)
    eq(past, false, "paint: refuses a frame past the end of the payload")
    ok(past_err and past_err:find("past the end", 1, true) ~= nil, "paint: says so")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- ---------- prepare ----------

  -- **The frame-rate contract, and it is invisible headless.**
  -- `nvim_set_hl` invalidates the whole screen, so a group created from
  -- inside a paint costs a full redraw. Measured on real footage: 10 to 476
  -- new pairs per second, never settling. `prepare` moves all of them to the
  -- sampling, which happens once per window and a second ahead of need -- so
  -- what this asserts is that a paint after `prepare` creates *nothing*.
  do
    for _, name in ipairs({ "half", "sextant" }) do
      with_cells(name, function()
        local cols, rows = 12, 4
        local geo = blocks.GEOMETRIES[name]
        local frames = 3
        math.randomseed(20260908)
        local parts = {}
        for _ = 1, frames * blocks.frame_bytes(cols, rows, geo) / 3 do
          parts[#parts + 1] = string.char(math.random(0, 255), math.random(0, 255), math.random(0, 255))
        end
        local raw = table.concat(parts)

        local created = blocks.prepare(raw, cols, rows)
        ok(created > 0, "prepare: creates the groups the payload needs (" .. name .. ")")

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))
        vim.bo[buf].modifiable = false
        local ns = vim.api.nvim_create_namespace("prep_" .. name)

        local before = blocks.groups_created()
        for frame = 1, frames do
          ok(blocks.paint(buf, ns, raw, frame, cols, rows), "prepare: frame " .. frame .. " paints (" .. name .. ")")
        end
        eq(
          blocks.groups_created(),
          before,
          "prepare: painting creates no group afterwards, so no frame forces a redraw (" .. name .. ")"
        )
        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end

    -- Running it twice must not double-count: the cache is the point.
    with_cells("sextant", function()
      local cols, rows = 8, 3
      local geo = blocks.GEOMETRIES.sextant
      local raw = string.char(10, 200, 90):rep(blocks.frame_bytes(cols, rows, geo) / 3)
      blocks.prepare(raw, cols, rows)
      eq(blocks.prepare(raw, cols, rows), 0, "prepare: a payload already prepared adds nothing")
    end)
  end

  -- ---------- the bound ----------

  do
    local cols, rows, levels = 16, 8, 4
    local ns = vim.api.nvim_create_namespace("blocks_spec_bound")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))

    -- Enough random cells that an unquantised painter would create a group
    -- for nearly every one of them: 30 frames x 128 cells = 3 840 colours.
    math.randomseed(20260908)
    local parts = {}
    for _ = 1, 30 * blocks.frame_bytes(cols, rows) / 3 do
      parts[#parts + 1] = string.char(math.random(0, 255), math.random(0, 255), math.random(0, 255))
    end
    local raw = table.concat(parts)

    local before = blocks.groups_created()
    for frame = 1, 30 do
      ok(blocks.paint(buf, ns, raw, frame, cols, rows, levels), "paint: frame " .. frame .. " of the bound test")
    end
    local created = blocks.groups_created() - before

    -- A half block's group is a colour *pair*, so the bound is not `levels^3`
    -- but the pairs that actually occur. What has to hold is that pure noise
    -- -- the worst input there is -- stays far below Neovim's own ceiling of
    -- 19 602, which `GROUP_BUDGET` would catch before it even so.
    ok(created < 5000, ("paint: %d groups for 30 noise frames, far under the 19602 ceiling"):format(created))
    ok(created > 0, "paint: the bound test actually created groups")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ---------- sampling, when ImageMagick is here ----------

  if blocks.available() then
    H.tmpdir(function(dir)
      local paths = {}
      for i = 1, 3 do
        local png = dir .. "/f" .. i .. ".png"
        local colour = ({ "red", "lime", "blue" })[i]
        vim.system({ "magick", "-size", "32x16", "xc:" .. colour, png }):wait()
        paths[#paths + 1] = png
      end

      local cols, rows = 8, 4
      local raw, err = blocks.sample(paths, cols, rows)
      ok(raw ~= nil, "sample: one process returns a payload (" .. tostring(err) .. ")")
      eq(#raw, 3 * blocks.frame_bytes(cols, rows), "sample: one frame's bytes per input path, in order")

      -- Frame 2 is the green one: its first cell must be green, which is also
      -- the proof that the frames come back in the order they were passed.
      local base = blocks.frame_bytes(cols, rows) + 1
      ok(raw:byte(base) < 128, "sample: frame 2 has little red")
      ok(raw:byte(base + 1) > 128, "sample: frame 2 is the green one")
      ok(raw:byte(base + 2) < 128, "sample: frame 2 has little blue")
    end)
  end

  -- ── Painting never writes the buffer ──────────────────────────────────────
  --
  -- The frame-rate bug this locks down (2026-09-08): every geometry but the
  -- half block used to write its glyphs with `nvim_buf_set_lines` once per
  -- frame. A reader measured the consequence by switching to half blocks --
  -- same extmark count, same redraw, no buffer write -- and went from 1-2 fps
  -- to smooth. `changedtick` is that difference in a form a test can hold:
  -- twelve writes a second bump it, twelve overlays do not.
  for _, cells in ipairs({ "half", "quadrant", "sextant" }) do
    require("images").setup({ display = { ascii_fallback = { cells = cells } } })
    local geo = blocks.geometry()

    local cols, rows, frames = 6, 3, 3
    local raw = string.rep("\170", frames * blocks.frame_bytes(cols, rows, geo))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))
    vim.bo[buf].modifiable = false
    local ns = vim.api.nvim_create_namespace("blocks_spec." .. cells)

    local before = vim.api.nvim_buf_get_changedtick(buf)
    local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i = 1, frames do
      ok(blocks.paint(buf, ns, raw, i, cols, rows), cells .. ": paint reports success")
    end

    eq(vim.api.nvim_buf_get_changedtick(buf), before, cells .. ": painting leaves the buffer untouched")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
      table.concat(text, "\n"),
      cells .. ": and the canvas text is the one canvas_lines wrote"
    )
    ok(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0, cells .. ": the picture is extmarks, and there are some")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  require("images").setup({})
end
