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
  local blocks = require("images.blocks")

  -- ---------- argv ----------

  do
    local argv = blocks.sample_argv({ "/a.png", "/b.png" }, 40, 20)
    eq(argv[1], "magick", "sample_argv: the binary")
    eq(argv[2], "/a.png[0]", "sample_argv: first frame of every input")
    eq(argv[3], "/b.png[0]", "sample_argv: every path is passed to one process")
    local joined = table.concat(argv, " ")
    ok(joined:find("-resize 40x20!", 1, true) ~= nil, "sample_argv: exact resize, aspect already applied")
    ok(joined:find("-alpha off", 1, true) ~= nil, "sample_argv: no alpha, so 3 bytes per pixel")
    eq(argv[#argv], "RGB:-", "sample_argv: raw bytes on stdout")

    eq(blocks.frame_bytes(40, 20), 40 * 20 * 3, "frame_bytes: three bytes per cell")
  end

  -- ---------- payload validation ----------

  do
    local raw, err = blocks.read_sampled({ code = 1, stderr = "boom" }, 1, 4, 4)
    eq(raw, nil, "read_sampled: nothing on a failed process")
    ok(err and err:find("boom", 1, true) ~= nil, "read_sampled: reports what magick said")

    -- The failure that matters: the process succeeded but wrote a short
    -- payload. Silently accepting it paints the previous frame's leftovers.
    raw, err = blocks.read_sampled({ code = 0, stdout = ("x"):rep(10) }, 1, 4, 4)
    eq(raw, nil, "read_sampled: a short payload is an error, not a partial frame")
    ok(err and err:find("of 48 bytes", 1, true) ~= nil, "read_sampled: says how short")

    local full = ("x"):rep(48)
    raw, err = blocks.read_sampled({ code = 0, stdout = full }, 1, 4, 4)
    eq(raw, full, "read_sampled: passes a complete payload through")
    eq(err, nil, "read_sampled: no error alongside a payload")
  end

  -- ---------- canvas ----------

  do
    local lines = blocks.canvas_lines(5, 3)
    eq(#lines, 3, "canvas_lines: one line per row")
    eq(vim.fn.strchars(lines[1]), 5, "canvas_lines: one cell character per column")
    eq(lines[1], blocks.BLOCK:rep(5), "canvas_lines: every cell is the block character")
  end

  -- ---------- paint ----------

  do
    local cols, rows = 4, 2
    local ns = vim.api.nvim_create_namespace("blocks_spec")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(cols, rows))

    -- Two frames: the first all one colour, the second a different one.
    local frame_a = string.char(255, 0, 0):rep(cols * rows)
    local frame_b = string.char(0, 0, 255):rep(cols * rows)
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
    for _ = 1, 30 * cols * rows do
      parts[#parts + 1] = string.char(math.random(0, 255), math.random(0, 255), math.random(0, 255))
    end
    local raw = table.concat(parts)

    local before = blocks.groups_created()
    for frame = 1, 30 do
      ok(blocks.paint(buf, ns, raw, frame, cols, rows, levels), "paint: frame " .. frame .. " of the bound test")
    end
    local created = blocks.groups_created() - before

    -- The guarantee: at `levels` steps per channel there are only `levels^3`
    -- possible colours, so no number of frames can create more groups than
    -- that -- regardless of what the pixels were.
    ok(created <= levels ^ 3, ("paint: %d groups created, bounded by levels^3 = %d"):format(created, levels ^ 3))
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
end
