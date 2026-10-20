-- TESTS/zen_viewport_spec.lua — the zen window's zoom and pan: which rectangle is
-- shown, which crop is cut, and that a crop in flight is never queued behind.
--
-- The window is real, the image is a real PNG (`images.testcard`), and
-- everything that would reach the terminal or ImageMagick is a stand-in:
-- `images.anchor.draw` records what it was asked to draw, `images.convert.crop`
-- records the geometry and hands its callback to the spec, which decides when
-- the "crop" finishes.

---@param H table harness from TESTS/run.lua
return function(H)
  local stubbed = {
    "images.anchor",
    "images.terminal",
    "images.guard",
    "images.info",
    "images.convert",
    "lib.nvim.cross.executable",
    "lib.nvim.notify",
    "images.zen",
  }
  local saved = {}
  for _, name in ipairs(stubbed) do
    saved[name] = package.loaded[name]
  end

  local drawn = {}
  package.loaded["images.anchor"] = {
    draw = function(_, _, file)
      drawn[#drawn + 1] = file
    end,
  }
  package.loaded["images.terminal"] = {
    clear = function() end,
    capability = function()
      return { ok = true }
    end,
  }
  package.loaded["images.guard"] = { check = function() end }
  package.loaded["images.info"] = {
    collect = function()
      return nil
    end,
  }
  local crops = {}
  package.loaded["images.convert"] = {
    crop = function(_, spec, out, _, on_done)
      crops[#crops + 1] = { spec = spec, out = out, done = on_done }
    end,
  }
  local has_magick = true
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function(bin)
      return bin == "magick" and has_magick
    end,
  }
  local warnings = {}
  local real_notify = saved["lib.nvim.notify"] or require("lib.nvim.notify")
  package.loaded["lib.nvim.notify"] = setmetatable({
    create = function(...)
      local n = real_notify.create(...)
      return setmetatable({
        warn = function(msg)
          warnings[#warnings + 1] = msg
        end,
        error = function(msg)
          warnings[#warnings + 1] = "error: " .. msg
        end,
      }, { __index = n })
    end,
  }, { __index = real_notify })
  package.loaded["images.zen"] = nil
  local zen = require("images.zen")

  -- Lets zen's deferred draw slot release.
  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  local function geometry()
    local rect = zen.viewport()
    return rect and require("images.viewport").geometry(rect) or "nil"
  end
  -- Finish crop number `i` the way convert.crop does: a file on disk, then the callback.
  local function finish(i)
    local c = crops[i]
    vim.fn.mkdir(vim.fs.dirname(c.out), "p")
    H.write(c.out, "crop")
    c.done(c.out, nil)
  end

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(600, 300))
    fd:close()

    H.ok(zen.open(file), "zen opens a real PNG")
    local buf = vim.api.nvim_get_current_buf()
    settle()
    H.eq(geometry(), "600x300+0+0", "the whole picture is visible at first")
    H.eq(drawn[#drawn], file, "... and the file itself is drawn")

    -- ── The keys are bound, through the registry ─────────────────────────
    local mapped = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      mapped[m.lhs] = true
    end
    for _, lhs in ipairs({ "+", "-", "0", "=", "h", "j", "k", "l", "<Left>", "H", "L", "<S-Up>" }) do
      H.ok(mapped[lhs], "bound in the zen buffer: " .. lhs)
    end
    local registered = {}
    for _, e in ipairs(require("lib.nvim.bindings.keymap").registered("images/zen")) do
      if e.bound then registered[e.name] = true end
    end
    H.ok(registered.zoom_in and registered.pan_left, "the zen actions are in the keymap registry (surface zen)")

    -- ── Zoom: one crop at a time, latest wins ────────────────────────────
    H.ok(zen.zoom(2), "zoom in by 2")
    H.eq(geometry(), "300x150+150+75", "the centre half is visible")
    H.eq(#crops, 1, "one crop is cut")
    H.eq(crops[1].spec, "300x150+150+75", "... of exactly that rectangle")

    H.ok(zen.zoom(2), "zoom in again while the first crop runs")
    H.eq(geometry(), "150x75+225+113", "the view follows at once")
    H.eq(#crops, 1, "... but no second magick is started")

    finish(1)
    H.eq(#crops, 2, "when the first crop finishes, the rectangle arrived at is cut next")
    H.eq(crops[2].spec, "150x75+225+113", "... the latest one, not the stale one")
    settle()
    finish(2)
    settle()
    H.eq(drawn[#drawn], crops[2].out, "that crop is what gets drawn")

    -- ── Cache: a rectangle seen before costs no second crop ──────────────
    zen.zoom_reset()
    settle()
    zen.zoom(2)
    settle()
    H.eq(geometry(), "300x150+150+75", "the first zoom step again")
    H.eq(#crops, 2, "no new crop: that rectangle is cached")
    H.eq(drawn[#drawn], crops[1].out, "... and its cached file is drawn")

    -- ── Pan ──────────────────────────────────────────────────────────────
    H.ok(zen.pan(math.huge, 0), "pan to the right edge")
    H.eq(geometry(), "300x150+300+75", "the view sits at the right edge")
    H.falsy(zen.pan(math.huge, 0), "nothing further right")
    H.ok(zen.pan(-0.25, 0), "a quarter step back left")
    H.eq(geometry(), "300x150+225+75", "75 px = a quarter of 300")
    -- The pan to the edge started a crop; while it runs nothing else is cut.
    local pending = #crops
    H.eq(crops[pending].spec, "300x150+300+75", "the pan to the edge started a crop")
    settle()
    finish(pending)
    H.eq(crops[#crops].spec, "300x150+225+75", "... and its end cuts where the view went since")
    finish(#crops)

    -- ── Reset ────────────────────────────────────────────────────────────
    settle()
    H.ok(zen.zoom_reset(), "back to the whole picture")
    H.eq(geometry(), "600x300+0+0", "the whole picture")
    settle()
    H.eq(drawn[#drawn], file, "the file itself is drawn again, no crop")
    H.falsy(zen.zoom_reset(), "resetting the whole picture changes nothing")
    H.falsy(zen.pan(0.25, 0), "nothing to pan while the whole picture is visible")

    -- ── Keys reach the same functions ────────────────────────────────────
    local before = #crops
    vim.api.nvim_feedkeys("+", "x", false)
    H.eq(geometry(), "400x200+100+50", "+ zooms in by one step (1.5)")
    vim.api.nvim_feedkeys("0", "x", false)
    H.eq(geometry(), "600x300+0+0", "0 resets")
    H.ok(#crops > before, "the key went through the crop path")

    -- ── Without ImageMagick: says so once, changes nothing ───────────────
    has_magick = false
    local n = #warnings
    H.falsy(zen.zoom(2), "no magick: no zoom")
    H.falsy(zen.zoom(2), "... still none")
    H.eq(#warnings - n, 1, "... and it is said once, not per press")
    H.ok(tostring(warnings[#warnings]):find("ImageMagick", 1, true) ~= nil, "... naming ImageMagick")
    has_magick = true
    zen.close()

    -- ── An image whose size is unknown cannot be zoomed ──────────────────
    local blob = dir .. "/blob.png"
    H.write(blob, "not really a png")
    H.ok(zen.open(blob), "zen opens a file without a readable header")
    H.eq(zen.viewport(), nil, "no rectangle without dimensions")
    H.falsy(zen.zoom(2), "and no zoom")
    zen.close()
    H.falsy(zen.is_open(), "closed")
  end)

  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
