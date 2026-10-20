-- TESTS/zen_mouse_spec.lua — the zen window's mouse: Alt+wheel zooms around the picture point
-- under the pointer, the middle button drags the picture.
--
-- Headless, `nvim_input_mouse` fires no mappings, so the screen-cell functions behind the
-- mappings are driven directly (`zoom_at_screen`, `drag_begin/to/end`), with cells computed
-- from the real `images.anchor.content_origin` and `images.viewport.image_box`. Only the
-- drawing and the crop are stand-ins.

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
  }
  local saved = {}
  for _, name in ipairs(stubbed) do
    saved[name] = package.loaded[name]
  end

  package.loaded["images.anchor"] = nil
  local real_anchor = require("images.anchor")
  package.loaded["images.anchor"] = setmetatable({ draw = function() end }, { __index = real_anchor })
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
  package.loaded["images.convert"] = {
    crop = function(_, _, out, _, on_done)
      vim.fn.mkdir(vim.fs.dirname(out), "p")
      H.write(out, "crop")
      on_done(out, nil)
    end,
  }
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function(bin)
      return bin == "magick"
    end,
  }
  package.loaded["images.zen"] = nil
  local zen = require("images.zen")
  local vp = require("images.viewport")

  local px = { width = 600, height = 300 }
  local function show(rect)
    return rect and vp.geometry(rect) or "nil"
  end
  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  -- The picture box of the zen window and its content origin, the way zen measures them.
  local function measure()
    local win = vim.api.nvim_get_current_win()
    local row0, col0 = real_anchor.content_origin(win)
    local rect = zen.viewport()
    local box = vp.image_box(vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win), real_anchor.inset(), rect)
    return box, row0, col0, rect
  end
  -- The screen cell over the picture point at fractions fx/fy of the visible rectangle.
  local function cell_at(fx, fy)
    local box, row0, col0 = measure()
    return row0 + box.row_off + math.floor(fy * box.rows), col0 + box.col_off + math.floor(fx * box.cols)
  end

  local zen_cfg = require("images.config").get().display.zen
  local saved_keys = vim.deepcopy(zen_cfg.keys)

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(px.width, px.height))
    fd:close()

    H.ok(zen.open(file), "zen opens")
    settle()
    local buf = vim.api.nvim_get_current_buf()

    -- ── The keys are bound, the derived ones too ─────────────────────────
    local mapped = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      mapped[m.lhs] = m
    end
    for _, lhs in ipairs({ "<M-ScrollWheelUp>", "<M-ScrollWheelDown>", "<MiddleMouse>", "<MiddleDrag>", "<MiddleRelease>" }) do
      H.ok(mapped[lhs] ~= nil, "bound in the zen buffer: " .. lhs)
    end
    local sheet = table.concat(zen.cheatsheet().lines, "\n")
    H.ok(sheet:find("Mouse", 1, true) ~= nil, "the key list has a Mouse group")
    H.ok(sheet:find("Alt + wheel up", 1, true) ~= nil, "... saying in words what the wheel does")

    -- A wheel that is not aimed at the window does nothing (headless, the pointer is nowhere).
    local cb = mapped["<M-ScrollWheelUp>"].callback
    H.ok(type(cb) == "function", "the wheel mapping is a Lua callback")
    cb()
    H.eq(show(zen.viewport()), "600x300+0+0", "a wheel aimed elsewhere changes nothing")

    -- ── Zoom at the pointer: the point under it stays put ────────────────
    local row, col = cell_at(0.25, 0.25)
    local box, row0, col0, before = measure()
    local fx, fy = vp.fraction_at(box, row - row0 + 1, col - col0 + 1)
    local point_x = before.x + fx * before.w
    local point_y = before.y + fy * before.h
    H.ok(zen.zoom_at_screen(2, row, col), "Alt+wheel up at a point of the picture zooms in")
    local after = zen.viewport()
    H.eq(after.w, 300, "by the factor")
    H.ok(math.abs((point_x - after.x) / after.w - fx) <= 1 / after.w, "the point keeps its horizontal place under the pointer")
    H.ok(math.abs((point_y - after.y) / after.h - fy) <= 1 / after.h, "... and its vertical place")
    H.ok(after.x < 150 and after.y < 75, "... so the view moved towards that corner, not the centre")

    -- A pointer on the frame, off the picture: the centre.
    zen.zoom_reset()
    local r0, c0 = real_anchor.content_origin(vim.api.nvim_get_current_win())
    H.ok(zen.zoom_at_screen(2, r0 - 1, c0 - 1), "a pointer on the border still zooms")
    H.eq(show(zen.viewport()), "300x150+150+75", "... around the centre")

    -- ── Middle-button drag ───────────────────────────────────────────────
    settle()
    local dbox, _, _, start = measure()
    row, col = cell_at(0.5, 0.5)
    H.ok(zen.drag_begin(row, col), "a drag starts")
    H.ok(zen.drag_to(row, col + 3), "the pointer moves three cells right")
    H.eq(show(zen.viewport()), show(vp.drag(px, start, dbox, 3, 0)), "the picture follows: the view shows what is further left")
    zen.drag_to(row + 2, col + 3)
    H.eq(show(zen.viewport()), show(vp.drag(px, start, dbox, 3, 2)), "measured from where the drag began, not step by step")
    zen.drag_end(row + 2, col + 3)
    H.falsy(zen.drag_to(row + 5, col + 5), "after the release nothing follows the pointer")

    zen.zoom_reset()
    H.ok(zen.drag_begin(row, col), "a drag can start on the whole picture")
    H.falsy(zen.drag_to(row, col + 3), "... but there is nothing to move")
    zen.drag_end(row, col + 3)
    zen.close()

    -- ── A remapped drag key derives its drag and release events ──────────
    zen_cfg.keys.drag = "<M-LeftMouse>"
    H.ok(zen.open(file), "zen opens with drag on <M-LeftMouse>")
    local remapped = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_get_current_buf(), "n")) do
      remapped[m.lhs] = true
    end
    H.ok(
      remapped["<M-LeftMouse>"] and remapped["<M-LeftDrag>"] and remapped["<M-LeftRelease>"],
      "<M-LeftMouse> brings <M-LeftDrag> and <M-LeftRelease>"
    )
    H.falsy(remapped["<MiddleDrag>"], "the default's drag event is gone with it")
    zen.close()
  end)

  zen_cfg.keys = saved_keys
  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
