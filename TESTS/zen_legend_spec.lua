-- TESTS/zen_legend_spec.lua — the zen window's legend (zoom factor in the title, "? help" in the
-- footer) and its `?` key list.
--
-- Real windows, a real PNG; the terminal, ImageMagick and the drawing are stand-ins. One rule
-- is checked by recording the order of events: WezTerm drops the picture on any
-- `nvim_win_set_config`, so every change of the frame has to be followed by a draw.

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

  local events = {}
  package.loaded["images.anchor"] = {
    draw = function()
      events[#events + 1] = "draw"
    end,
  }
  package.loaded["images.terminal"] = {
    clear = function()
      events[#events + 1] = "clear"
    end,
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
  -- A crop that succeeds at once: the file appears, the callback runs.
  package.loaded["images.convert"] = {
    crop = function(_, _, out, _, on_done)
      vim.fn.mkdir(vim.fs.dirname(out), "p")
      H.write(out, "crop")
      on_done(out, nil)
    end,
  }
  local has_magick = true
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function(bin)
      return bin == "magick" and has_magick
    end,
  }
  package.loaded["images.zen"] = nil
  local zen = require("images.zen")

  -- Record every frame change, to check the "config, then draw" order.
  local real_set_config = vim.api.nvim_win_set_config
  vim.api.nvim_win_set_config = function(win, config)
    if config.title or config.footer then events[#events + 1] = "config" end
    return real_set_config(win, config)
  end

  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  local function frame()
    local c = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    local title = c.title and c.title[1] and c.title[1][1] or nil
    local footer = c.footer and c.footer[1] and c.footer[1][1] or nil
    return title, footer
  end
  -- Every "config" event is followed, later, by a "draw".
  local function each_config_drawn()
    local pending = false
    for _, e in ipairs(events) do
      if e == "config" then
        pending = true
      elseif e == "draw" then
        pending = false
      end
    end
    return not pending
  end
  local function sheet_text()
    return table.concat(zen.cheatsheet().lines, "\n")
  end

  local zen_cfg = require("images.config").get().display.zen
  local saved_keys, saved_legend = vim.deepcopy(zen_cfg.keys), zen_cfg.legend

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(600, 300))
    fd:close()

    -- ── Legend ───────────────────────────────────────────────────────────
    H.ok(zen.open(file), "zen opens")
    settle()
    local title, footer = frame()
    H.eq(title, " shot.png ", "the whole picture: just the name")
    H.eq(footer, " ? help ", "the footer points at the key list")

    events = {}
    zen.zoom(2)
    settle()
    title = frame()
    H.eq(title, " shot.png · 2× ", "zoomed: the factor is in the title")
    H.ok(vim.tbl_contains(events, "config") and each_config_drawn(), "the frame changed, and a draw followed")

    zen.zoom_reset()
    zen.zoom(1.5)
    settle()
    H.eq((frame()), " shot.png · 1.5× ", "a fractional factor keeps one decimal")
    H.ok(each_config_drawn(), "still: no frame change without a draw after it")

    events = {}
    zen.pan(0.25, 0)
    settle()
    H.falsy(vim.tbl_contains(events, "config"), "a pan keeps the factor, so the frame is left alone")
    zen.close()

    -- A narrow window has room for "?" only.
    H.ok(zen.open(file, { width = 0.1, height = 0.3 }), "zen opens narrow")
    settle()
    H.eq(select(2, frame()), " ? ", "the narrow footer")
    zen.close()

    -- `legend = false`: the frame is the file name and nothing else, and is never touched.
    zen_cfg.legend = false
    H.ok(zen.open(file), "zen opens without a legend")
    settle()
    events = {}
    zen.zoom(2)
    settle()
    title, footer = frame()
    H.eq(title, " shot.png ", "no factor in the title")
    H.eq(footer, nil, "no footer")
    H.falsy(vim.tbl_contains(events, "config"), "and the frame is not changed at all")
    zen.close()
    zen_cfg.legend = saved_legend

    -- ── The key list ─────────────────────────────────────────────────────
    H.ok(zen.open(file), "zen opens for the key list")
    settle()
    local text = sheet_text()
    H.ok(text:find("Zoom", 1, true) ~= nil, "the list has a Zoom group")
    H.ok(text:find("zoom in", 1, true) ~= nil, "... naming zoom in")
    H.ok(text:find("this list of keys", 1, true) ~= nil, "... and the ? key itself")
    H.ok(text:find("close this list", 1, true) ~= nil, "... with how to close it")
    H.falsy(text:find("ImageMagick", 1, true), "no ImageMagick note while magick is there")
    has_magick = false
    H.ok(sheet_text():find("ImageMagick", 1, true) ~= nil, "without magick the list says zoom needs it")
    has_magick = true
    zen.close()

    -- What is bound is what is listed: a remapped key shows its new key, a dropped one is absent.
    zen_cfg.keys.zoom_in = "Z"
    zen_cfg.keys.pan_left = false
    H.ok(zen.open(file), "zen opens with remapped keys")
    settle()
    local rows = {}
    for _, row in ipairs(zen.cheatsheet().rows) do
      rows[row.name] = table.concat(row.keys, " ")
    end
    H.eq(rows.zoom_in, "Z", "zoom_in is listed with its new key")
    H.eq(rows.pan_left, nil, "a disabled key is not listed")
    H.eq(rows.pan_right, "l <Right>", "an untouched key keeps its defaults")

    -- ── `?` opens the list, takes the picture away, and puts it back ─────
    local zen_win = vim.api.nvim_get_current_win()
    events = {}
    H.ok(zen.help(), "? opens the key list")
    local help_win = vim.api.nvim_get_current_win()
    H.ok(help_win ~= zen_win, "the list has its own window, and the focus")
    H.ok(vim.tbl_contains(events, "clear"), "the picture is taken off the screen")
    events = {}
    vim.api.nvim_exec_autocmds("WinResized", {})
    settle()
    H.falsy(vim.tbl_contains(events, "draw"), "nothing draws over the open list")

    vim.api.nvim_feedkeys("?", "x", false)
    settle()
    H.falsy(vim.api.nvim_win_is_valid(help_win), "? in the list closes it")
    H.eq(vim.api.nvim_get_current_win(), zen_win, "the focus is back on the picture")
    H.ok(vim.tbl_contains(events, "draw"), "and the picture is drawn again")

    H.ok(zen.help(), "the list opens again")
    help_win = vim.api.nvim_get_current_win()
    zen.close()
    H.falsy(vim.api.nvim_win_is_valid(help_win), "closing zen closes an open list with it")
  end)

  vim.api.nvim_win_set_config = real_set_config
  zen_cfg.keys, zen_cfg.legend = saved_keys, saved_legend
  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
