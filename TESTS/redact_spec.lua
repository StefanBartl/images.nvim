-- TESTS/redact_spec.lua — `:Image redact`: boxes are chosen like a part of the zen picture,
-- without painting over it, and shown burned into a preview.
--
-- Real windows and the real `images.anchor` geometry, as in zen_select_spec.lua; the burn-in
-- is a stand-in that records what it was asked and lets the spec decide when it finishes
-- (the real one is covered in convert_spec.lua). Headless, mouse events fire no mappings, so
-- the screen-cell functions are driven directly.

---@param H table harness from TESTS/run.lua
return function(H)
  local stubbed = {
    "images.anchor",
    "images.terminal",
    "images.guard",
    "images.info",
    "images.convert",
    "lib.nvim.cross.executable",
    "images.zen",
    "images.redact",
    "images",
  }
  local saved = {}
  for _, name in ipairs(stubbed) do
    saved[name] = package.loaded[name]
  end

  local capable = true
  local shown = 0
  package.loaded["images.anchor"] = nil
  local real_anchor = require("images.anchor")
  local drawn = {}
  package.loaded["images.anchor"] = setmetatable({
    draw = function(_, _, file)
      drawn[#drawn + 1] = file
    end,
  }, { __index = real_anchor })
  package.loaded["images.terminal"] = {
    clear = function() end,
    capability = function()
      return { ok = capable }
    end,
  }
  package.loaded["images.guard"] = { check = function() end }
  package.loaded["images.info"] = {
    collect = function()
      return { width = 600, height = 300 }
    end,
  }
  local burns, crops = {}, {}
  package.loaded["images.convert"] = {
    redact = function(src, boxes, on_done, out)
      burns[#burns + 1] = { src = src, boxes = vim.deepcopy(boxes), done = on_done, out = out }
    end,
    crop = function(...)
      crops[#crops + 1] = { ... }
    end,
  }
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function(bin)
      return bin == "magick"
    end,
  }
  package.loaded["images.zen"] = nil
  package.loaded["images.redact"] = nil
  local zen = require("images.zen")
  local redact = require("images.redact")
  local vp = require("images.viewport")

  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  -- Finish burn `i` the way magick would: the file appears, then the callback.
  local function finish(i)
    local b = burns[i]
    local path = b.out or (b.src:gsub("%.png$", ".redacted.png"))
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({}, path)
    b.done(path, nil)
    settle()
    return path
  end
  local function cell_at(fx, fy)
    local win = vim.api.nvim_get_current_win()
    local row0, col0 = real_anchor.content_origin(win)
    local box =
      vp.image_box(vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win), real_anchor.inset(), zen.viewport())
    return row0 + box.row_off + math.floor(fy * box.rows), col0 + box.col_off + math.floor(fx * box.cols)
  end
  local function title()
    local c = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    return c.title and c.title[1] and c.title[1][1] or ""
  end
  local function mark(fx1, fy1, fx2, fy2)
    local r1, c1 = cell_at(fx1, fy1)
    local r2, c2 = cell_at(fx2, fy2)
    zen.select_begin(r1, c1)
    zen.select_to(r2, c2)
    return zen.select_end(r2, c2)
  end

  -- ── pixel_box: padding in cells of the view, clamped to the picture ─────
  local px = { width = 600, height = 300 }
  local b = redact.pixel_box({ x = 100, y = 50, w = 40, h = 20 }, { w = 5, h = 10 }, 1, px)
  H.eq(vim.inspect(b), vim.inspect({ x1 = 95, y1 = 40, x2 = 144, y2 = 79 }), "one cell of padding on each side")
  b = redact.pixel_box({ x = 2, y = 0, w = 598, h = 300 }, { w = 5, h = 10 }, 1, px)
  H.eq(vim.inspect(b), vim.inspect({ x1 = 0, y1 = 0, x2 = 599, y2 = 299 }), "clamped to the picture")
  b = redact.pixel_box({ x = 10, y = 10, w = 5, h = 5 }, { w = 2.5, h = 2.5 }, 0, px)
  H.eq(vim.inspect(b), vim.inspect({ x1 = 10, y1 = 10, x2 = 14, y2 = 14 }), "no padding: the selection itself")
  for _, bad in ipairs({ "2", true, {}, -3, 0 / 0 }) do
    local ok, got = pcall(redact.pixel_box, { x = 10, y = 10, w = 5, h = 5 }, { w = 2, h = 2 }, bad, px)
    H.ok(ok and got.x1 == 10 and got.x2 == 14, "padding " .. vim.inspect(bad) .. " counts as none")
  end

  H.falsy(redact.is_open(), "no redaction window is open")
  redact.close() -- must not fail

  local cfg = require("images.config").get()
  local saved_padding = cfg.display.redact.padding_cells
  cfg.display.redact.padding_cells = 0

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(600, 300))
    fd:close()

    H.ok(redact.open(file), "redact opens")
    settle()
    local win = vim.api.nvim_get_current_win()
    H.ok(redact.is_open(), "is_open")
    H.ok(title():find("redact · 0 boxes", 1, true) ~= nil, "the title says redact and counts the boxes")
    H.eq(drawn[#drawn], file, "it shows the original")

    -- ── v: a keyboard selection, not visual mode ─────────────────────────
    vim.api.nvim_feedkeys("v", "x", false)
    H.eq(vim.fn.mode(), "n", "v does not enter visual mode (it would paint over the picture)")
    H.ok(zen.selection() ~= nil, "... it starts a selection on the frame")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "x", false)
    H.eq(zen.selection(), nil, "<Esc> drops it")

    -- ── A dragged box: burned into a preview, no part window ─────────────
    H.ok(mark(0.1, 0.2, 0.5, 0.7), "a drag marks a box")
    H.eq(vim.api.nvim_get_current_win(), win, "no window is opened for it")
    H.eq(#crops, 0, "nothing is cut")
    H.eq(#burns, 1, "the preview is asked for")
    H.eq(burns[1].src, file, "... from the original")
    H.ok(burns[1].out and burns[1].out:find(dir, 1, true) == nil, "... into a temporary file, not next to it")
    local box = redact.boxes()[1]
    H.ok(box and box.x1 >= 50 and box.x1 <= 70 and box.x2 >= 290 and box.x2 <= 310, "the box is in the original's pixels")
    local preview1 = finish(1)
    H.eq(drawn[#drawn], preview1, "the window shows the preview")
    H.ok(title():find("redact · 1 box", 1, true) ~= nil, "the title counts it")

    -- ── Latest wins ──────────────────────────────────────────────────────
    mark(0.6, 0.1, 0.9, 0.3)
    mark(0.6, 0.6, 0.9, 0.9)
    H.eq(#burns, 3, "one preview per box")
    local preview3 = finish(3)
    finish(2)
    H.eq(drawn[#drawn], preview3, "a slower, older preview does not replace the newer one")
    H.ok(title():find("3 boxes", 1, true) ~= nil, "three boxes")

    -- ── u takes the last box off ─────────────────────────────────────────
    vim.api.nvim_feedkeys("u", "x", false)
    H.eq(#redact.boxes(), 2, "u removes the last box")
    H.eq(#burns[#burns].boxes, 2, "... and the preview is drawn from the rest")
    finish(#burns)
    vim.api.nvim_feedkeys("2u", "x", false)
    H.eq(#redact.boxes(), 0, "2u removes two")
    H.eq(drawn[#drawn], file, "with none left the original is shown")

    -- ── What a redact window does not bind ───────────────────────────────
    for _, lhs in ipairs({ "gs", "gy", "<BS>" }) do
      H.eq(vim.fn.maparg(lhs, "n"), "", lhs .. " is not bound (it would hand out the unredacted picture)")
    end

    -- ── w writes next to the original and closes ─────────────────────────
    local n = #burns
    vim.api.nvim_feedkeys("w", "x", false)
    H.eq(#burns, n, "w without a box writes nothing")
    mark(0.1, 0.2, 0.5, 0.7)
    finish(#burns)
    local preview_dir = vim.fs.dirname(burns[#burns].out)

    -- A keyboard selection still open is a box not taken yet: w waits for it.
    vim.api.nvim_feedkeys("v", "x", false)
    n = #burns
    vim.api.nvim_feedkeys("w", "x", false)
    H.eq(#burns, n, "w with a selection still open writes nothing")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "x", false)

    vim.api.nvim_feedkeys("w", "x", false)
    H.eq(#burns, n + 1, "w burns the boxes in")
    H.eq(burns[n + 1].out, nil, "... to the default target next to the original")
    H.ok(vim.api.nvim_win_is_valid(win), "the window stays up until it is written")
    -- While it is written the set is fixed: a box marked now would not be in the file.
    mark(0.6, 0.6, 0.9, 0.9)
    H.eq(#redact.boxes(), 1, "no box is added while w is writing")
    H.eq(#burns, n + 1, "... and no preview asked for")
    vim.api.nvim_feedkeys("u", "x", false)
    H.eq(#redact.boxes(), 1, "u removes none either")
    finish(n + 1)
    H.falsy(vim.api.nvim_win_is_valid(win), "then it closes")
    H.falsy(redact.is_open(), "is_open is false again")
    H.eq(vim.fn.isdirectory(preview_dir), 0, "the previews are deleted")

    -- ── A terminal that does not look image-capable: still a redact window ─
    -- (zen alone shows the block-graphics fallback there, which has no selection.)
    capable = false
    package.loaded["images"] = setmetatable({
      show = function()
        shown = shown + 1
        return true
      end,
    }, { __index = package.loaded["images"] })
    H.ok(redact.open(file), "redact opens on an unrecognised terminal")
    H.eq(shown, 0, "... as a redact window, not the fallback")
    redact.close()
    capable = true

    -- ── keys = false still leaves the selection keys ─────────────────────
    local zen_cfg = cfg.display.zen
    local saved_keys = zen_cfg.keys
    zen_cfg.keys = false
    H.ok(redact.open(file), "redact opens with display.zen.keys = false")
    settle()
    vim.api.nvim_feedkeys("v", "x", false)
    H.ok(zen.selection() ~= nil, "... and v still starts a selection")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "x", false)
    H.eq(vim.fn.maparg("+", "n"), "", "... while the other zen keys stay off")
    redact.close()
    zen_cfg.keys = saved_keys

    -- ── A vector image is refused, not opened without a way to select ──────
    local svg = dir .. "/logo.svg"
    vim.fn.writefile({ '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>' }, svg)
    H.falsy(redact.open(svg), "an SVG is refused")
    H.falsy(redact.is_open(), "... and nothing is left open")
  end)

  cfg.display.redact.padding_cells = saved_padding
  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
