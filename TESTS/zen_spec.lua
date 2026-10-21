-- TESTS/zen_spec.lua — window size arithmetic for `:Image zen`.
--
-- `M.dimensions` is pure arithmetic over `vim.o.columns`/`vim.o.lines` without
-- opening a window — testable like `images.gallery`'s grid layout. The drawing
-- itself (`images.terminal.draw`) stays unchecked, as everywhere in this suite.

---@param H table harness from TESTS/run.lua
return function(H)
  local zen = require("images.zen")

  -- ── Default fractions ────────────────────────────────────────────────────
  local w, h = zen.dimensions(nil)
  H.eq(w, math.floor(vim.o.columns * 0.9), "default width: 90% of the editor width")
  H.eq(h, math.floor(vim.o.lines * 0.85), "default height: 85% of the editor height")

  -- ── Configured fractions ─────────────────────────────────────────────────
  w, h = zen.dimensions({ width = 0.5, height = 0.5 })
  H.eq(w, math.floor(vim.o.columns * 0.5), "a configured width is honoured")
  H.eq(h, math.floor(vim.o.lines * 0.5), "a configured height is honoured")

  -- ── Never smaller than 1 cell, even at a fraction of 0 ───────────────────
  w, h = zen.dimensions({ width = 0, height = 0 })
  H.eq(w, 1, "the width has a lower bound of 1")
  H.eq(h, 1, "the height has a lower bound of 1")

  -- ── No window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(zen.is_open(), "no zen window is open")
  zen.close() -- must not fail
  H.falsy(zen.is_open(), "close() stays a no-op without an open window")

  -- ── `dimensions_for` shrinks to the image's aspect ratio ─────────────────
  -- No real file access needed: without ImageMagick (or for a non-existent
  -- path) `images.info.collect` simply returns no `width`/`height`, and
  -- `dimensions_for` then falls back to the maximum box — exactly the path
  -- checked here without a terminal or ImageMagick.
  local max_w, max_h = zen.dimensions(nil)
  local fw, fh = zen.dimensions_for("/path/that/does/not/exist.png", nil)
  H.eq(fw, max_w, "without discoverable pixel dimensions: the width stays the maximum box")
  H.eq(fh, max_h, "without discoverable pixel dimensions: the height stays the maximum box")

  -- ── `next_size`: the step after a box, by area ───────────────────────────
  local small, mid, full = { width = 0.66, height = 0.66 }, { width = 0.9, height = 0.85 }, { width = 1, height = 1 }
  local unsorted = { full, small, mid }
  H.eq(zen.next_size({ width = 0.5, height = 0.5 }, unsorted, 1), small, "grow from below the list: the smallest step")
  H.eq(zen.next_size(small, unsorted, 1), mid, "grow: the next larger step, whatever the list order")
  H.eq(zen.next_size(mid, unsorted, 1), full, "grow: up to full screen")
  H.eq(zen.next_size(full, unsorted, 1), nil, "grow at the largest step: none")
  H.eq(zen.next_size(full, unsorted, -1), mid, "shrink: the next smaller step")
  H.eq(zen.next_size(small, unsorted, -1), nil, "shrink at the smallest step: none")

  -- ── The open window grows and shrinks ────────────────────────────────────
  -- Drawing stays unchecked as everywhere here: anchor/terminal/guard/info are
  -- stand-ins, the window itself is real.
  local stubbed =
    { "images.anchor", "images.terminal", "images.guard", "images.info", "lib.nvim.notify", "images.ascii", "images" }
  local saved = {}
  for _, name in ipairs(stubbed) do
    saved[name] = package.loaded[name]
  end
  local draws, clears, errors = 0, 0, {}
  local last_on_done
  package.loaded["images.anchor"] = {
    draw = function(_, _, _, opts)
      draws = draws + 1
      last_on_done = opts and opts.on_done
    end,
  }
  local real_notify = saved["lib.nvim.notify"] or require("lib.nvim.notify")
  package.loaded["lib.nvim.notify"] = setmetatable({
    create = function(...)
      local n = real_notify.create(...)
      return setmetatable({
        error = function(msg)
          errors[#errors + 1] = msg
        end,
      }, { __index = n })
    end,
  }, { __index = real_notify })
  local cap_ok, ascii_ok, shown = true, false, {}
  package.loaded["images.terminal"] = {
    clear = function()
      clears = clears + 1
    end,
    capability = function()
      return { ok = cap_ok }
    end,
  }
  package.loaded["images.ascii"] = {
    available = function()
      return ascii_ok
    end,
  }
  package.loaded["images"] = {
    show = function(path)
      shown[#shown + 1] = path
      return true
    end,
  }
  -- Lets the scheduled release of zen's draw slot run.
  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  package.loaded["images.guard"] = { check = function() end }
  package.loaded["images.info"] = {
    collect = function()
      return nil
    end,
  }

  H.tmpdir(function(dir)
    local file = dir .. "/pic.png"
    H.write(file, "not really a png")
    local max_fw = require("lib.nvim.window.max_float_width")()
    local function expect(box)
      return math.min(math.floor(vim.o.columns * box.width), max_fw),
        math.min(math.floor(vim.o.lines * box.height), math.max(1, vim.o.lines - 4))
    end
    local function eq_size(box, msg)
      local c = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
      local ew, eh = expect(box)
      H.eq(c.width, ew, msg .. " (width)")
      H.eq(c.height, eh, msg .. " (height)")
    end

    H.ok(zen.open(file, { width = 0.5, height = 0.5 }), "zen opens at a size given by the caller")
    local buf = vim.api.nvim_get_current_buf()
    eq_size({ width = 0.5, height = 0.5 }, "opts.width/height size the window")

    local mapped = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      mapped[m.lhs] = true
    end
    H.ok(mapped["<S-Up>"] and mapped["<S-Down>"], "<S-Up>/<S-Down> are mapped in the zen buffer")

    settle()
    local d0, c0 = draws, clears
    H.ok(zen.resize(1), "grow from 1/2: a step")
    eq_size(small, "grow lands on the 2/3 step")
    H.ok(draws > d0 and clears > c0, "a resize clears the old picture and draws again")
    local cfg = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    H.eq(cfg.col, math.max(0, math.floor((vim.o.columns - cfg.width) / 2)), "a resized window is re-centred")

    -- The resize's own WinResized arrives before the queued draw has run:
    -- one picture sent, not two.
    -- (Headless Neovim fires no WinResized; the spec fires it, naming the
    -- resized windows the way v:event.windows would.)
    settle()
    local zen_win = vim.api.nvim_get_current_win()
    local function resized(wins)
      vim.api.nvim_exec_autocmds("WinResized", { data = { windows = wins } })
    end
    local d1 = draws
    zen.resize(1)
    resized({ zen_win })
    H.eq(draws - d1, 1, "a resize and its own WinResized draw the picture once")
    settle()
    resized({ zen_win })
    H.eq(draws - d1, 2, "a WinResized after the draw has run draws again")
    settle()
    resized({ zen_win + 100 })
    H.eq(draws - d1, 2, "a WinResized of another window (a message float) does not redraw")

    zen.resize(1)
    eq_size(full, "the full-screen step keeps the make_scratch caps")
    H.falsy(zen.resize(1), "grow at full screen: no step")
    H.ok(zen.resize(-1), "shrink from full screen: a step")
    eq_size(mid, "shrink lands on the 90% step")

    -- A draw still pending while the window is open reports its failure ...
    H.ok(type(last_on_done) == "function", "the draw got an on_done")
    last_on_done(false, "boom")
    H.eq(#errors, 1, "a failed draw into the open window is reported")
    -- ... one that settles after `q` closed the window is not an error.
    local pending = last_on_done
    zen.close()
    pending(false, "window is no longer valid")
    H.eq(#errors, 1, "a draw settling after the window closed reports nothing")
    H.falsy(zen.resize(1), "resize without an open window is a no-op")

    -- A terminal that probably cannot draw: the block fallback via
    -- images.show, as `:Image show` does, instead of an empty window.
    local function floats()
      local n = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then n = n + 1 end
      end
      return n
    end
    cap_ok, ascii_ok = false, true
    local before = floats()
    H.ok(zen.open(file), "no capability, fallback there: zen reports success")
    H.eq(shown[1], file, "... and hands the image to images.show")
    H.eq(floats(), before, "... without opening a zen window")
    ascii_ok = false
    H.ok(zen.open(file), "no capability, no fallback: zen draws anyway")
    H.ok(zen.is_open(), "... in its window (detection is a heuristic)")
    zen.close()
    cap_ok = true

    -- An empty or non-string key is skipped instead of failing the open.
    local zen_cfg = require("images.config").get().display.zen
    local saved_keys = zen_cfg.keys
    zen_cfg.keys = { grow = "", shrink = { 5, "<S-Down>" } }
    local ok_open, opened = pcall(zen.open, file)
    H.ok(ok_open and opened, "a bad key in display.zen.keys does not break the open")
    local mapped2 = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_get_current_buf(), "n")) do
      mapped2[m.lhs] = true
    end
    H.ok(mapped2["<S-Down>"], "... and the valid key is still mapped")
    zen.close()
    zen_cfg.keys = saved_keys
  end)

  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
