-- TESTS/zen_select_spec.lua — selecting a part of the zen picture and opening it as a zen
-- window of its own, stacked on the one it was cut from.
--
-- Real windows and the real `images.anchor` geometry; the crop is a stand-in that writes a
-- real PNG of the cut size (so the child window knows its dimensions) and lets the spec
-- decide when it finishes. Headless, mouse events fire no mappings, so the screen-cell
-- functions are driven directly and the mappings' callbacks are called by hand.

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
  local drawn = {}
  package.loaded["images.anchor"] = setmetatable({
    draw = function(_, _, file)
      drawn[#drawn + 1] = file
    end,
  }, { __index = real_anchor })
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
    crop = function(src, spec, out, _, on_done)
      crops[#crops + 1] = { src = src, spec = spec, out = out, done = on_done }
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
  local passed = {}
  zen._pass_through = function(lhs)
    passed[#passed + 1] = lhs
  end

  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  -- Finish crop `i` with a real PNG of the cut size, as ImageMagick would.
  local function finish(i)
    local c = crops[i]
    local w, h = c.spec:match("^(%d+)x(%d+)")
    vim.fn.mkdir(vim.fs.dirname(c.out), "p")
    local fd = assert(io.open(c.out, "wb"))
    fd:write(require("images.testcard").build(tonumber(w), tonumber(h)))
    fd:close()
    c.done(c.out, nil)
    settle()
  end
  local function geometry_now()
    local win = vim.api.nvim_get_current_win()
    local row0, col0 = real_anchor.content_origin(win)
    local rect = zen.viewport()
    local box = vp.image_box(vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win), real_anchor.inset(), rect)
    return box, row0, col0, rect
  end
  -- Screen cell over fractions fx/fy of the visible picture.
  local function cell_at(fx, fy)
    local box, row0, col0 = geometry_now()
    return row0 + box.row_off + math.floor(fy * box.rows), col0 + box.col_off + math.floor(fx * box.cols)
  end
  local function title()
    local c = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    return c.title and c.title[1] and c.title[1][1] or ""
  end

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(600, 300))
    fd:close()

    H.ok(zen.open(file), "zen opens")
    settle()
    local root = vim.api.nvim_get_current_win()
    local origin = zen.origin()
    H.ok(origin and origin.file == file and origin.x == 0 and origin.y == 0, "the first window is the original at 0,0")

    -- ── Mouse selection: the frame colours, nothing is painted ───────────
    local r1, c1 = cell_at(0.1, 0.2)
    local r2, c2 = cell_at(0.5, 0.7)
    H.ok(zen.select_begin(r1, c1), "a left press on the picture starts a selection")
    H.ok(vim.wo[root].winhighlight:find("FloatBorder:ImagesZenSelect", 1, true) ~= nil, "the frame takes the selection colour")
    zen.select_to(r2, c2)
    local box, row0, col0, rect = geometry_now()
    local want = vp.cells_to_rect(rect, box, r1 - row0 + 1, c1 - col0 + 1, r2 - row0 + 1, c2 - col0 + 1, 2)
    local _, sel = zen.selection()
    H.eq(sel and vp.geometry(sel), want and vp.geometry(want), "the selection is the source rectangle under the dragged cells")
    H.ok(zen.select_end(r2, c2), "the release opens it")
    H.falsy(vim.wo[root].winhighlight:find("ImagesZenSelect", 1, true), "the frame colour is back")
    H.eq(#crops, 1, "one crop is cut")
    H.eq(crops[1].src, file, "... from the original")
    H.eq(crops[1].spec, vp.geometry(want), "... exactly the selection, at full resolution")

    -- ── The child: stacked, the parent hidden ────────────────────────────
    finish(1)
    local child = vim.api.nvim_get_current_win()
    H.ok(child ~= root, "the selection opens in a window of its own")
    H.eq(vim.api.nvim_win_get_config(root).hide, true, "the window it was cut from is hidden")
    local child_origin = zen.origin()
    H.eq(child_origin.file, file, "the child knows the original")
    H.eq(child_origin.x, want.x, "... and where it sits in it")
    H.ok(title():find("shot.png", 1, true) ~= nil, "the child's title names the original")
    H.ok(title():find("2/2", 1, true) ~= nil, "... and its depth")
    H.eq(drawn[#drawn], crops[1].out, "the child draws its crop")

    -- A selection in the child is cut from the ORIGINAL, offset by where the child sits.
    local cr1, cc1 = cell_at(0.25, 0.25)
    local cr2, cc2 = cell_at(0.75, 0.75)
    zen.select_begin(cr1, cc1)
    zen.select_to(cr2, cc2)
    local _, inner = zen.selection()
    zen.select_end(cr2, cc2)
    H.eq(crops[2].src, file, "a nested selection is cut from the original too")
    H.eq(
      crops[2].spec,
      vp.geometry({ x = child_origin.x + inner.x, y = child_origin.y + inner.y, w = inner.w, h = inner.h }),
      "... at the child's offset plus the selection"
    )
    finish(2)
    local grandchild = vim.api.nvim_get_current_win()
    H.ok(title():find("3/3", 1, true) ~= nil, "three deep")

    -- ── <BS> goes back one level, the parent is drawn again ──────────────
    H.ok(zen.back(), "back")
    settle()
    H.falsy(vim.api.nvim_win_is_valid(grandchild), "the deepest window is closed")
    H.eq(vim.api.nvim_get_current_win(), child, "the focus is back on its parent")
    H.falsy(vim.api.nvim_win_get_config(child).hide, "which is shown again")
    H.eq(drawn[#drawn], crops[1].out, "and drawn again")
    zen.back()
    settle()
    H.eq(vim.api.nvim_get_current_win(), root, "back again to the first window")
    H.falsy(zen.back(), "the first window has nothing to go back to")
    H.eq(drawn[#drawn], file, "it draws the original")

    -- ── q closes the whole stack ─────────────────────────────────────────
    zen.select_begin(r1, c1)
    zen.select_end(r2, c2)
    finish(#crops)
    local top = vim.api.nvim_get_current_win()
    vim.api.nvim_feedkeys("q", "x", false)
    settle()
    H.falsy(vim.api.nvim_win_is_valid(top), "q closes the selection window")
    H.falsy(vim.api.nvim_win_is_valid(root), "... and the window under it")

    -- ── A click is not a selection ───────────────────────────────────────
    H.ok(zen.open(file), "zen opens again")
    settle()
    root = vim.api.nvim_get_current_win()
    local n = #crops
    r1, c1 = cell_at(0.3, 0.3)
    zen.select_begin(r1, c1)
    H.falsy(zen.select_end(r1, c1), "a press and release on one cell opens nothing")
    H.eq(#crops, n, "... and cuts nothing")

    -- ── Keyboard selection ───────────────────────────────────────────────
    H.ok(zen.select_keys(), "v starts a keyboard selection")
    local s = zen.selection()
    H.ok(s and s.keys and s.r1 == s.r2 and s.c1 == s.c2, "both corners start in the middle")
    vim.api.nvim_feedkeys("lllj", "x", false)
    s = zen.selection()
    H.eq(s.c2 - s.c1, 3, "l moves the second corner right, not the view")
    H.eq(s.r2 - s.r1, 1, "j moves it down")
    H.eq(vp.geometry(zen.viewport()), "600x300+0+0", "the view did not move")
    vim.api.nvim_feedkeys("L", "x", false)
    H.eq(zen.selection().c2 - s.c1, 8, "L moves it five cells")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "x", false)
    H.eq(zen.selection(), nil, "<Esc> drops the selection")
    H.ok(vim.api.nvim_win_is_valid(root), "... and keeps the window")
    zen.select_keys()
    vim.api.nvim_feedkeys("llljj", "x", false)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, true, true), "x", false)
    H.eq(#crops, n + 1, "<CR> opens the keyboard selection")

    -- ── A zoom while selecting drops the selection ───────────────────────
    finish(#crops)
    zen.back()
    settle()
    zen.select_keys()
    zen.zoom(2)
    H.eq(zen.selection(), nil, "a zoom drops the selection it would no longer match")

    -- ── A press beside the picture goes back to Neovim ───────────────────
    local press
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_get_current_buf(), "n")) do
      if m.lhs == "<LeftMouse>" then press = m.callback end
    end
    H.ok(type(press) == "function", "<LeftMouse> is mapped in the zen buffer")
    press()
    H.eq(passed[#passed], "<LeftMouse>", "a press not on the window is handed back unmapped")
    zen.close()
  end)

  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
