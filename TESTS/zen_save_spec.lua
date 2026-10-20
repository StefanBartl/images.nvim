-- TESTS/zen_save_spec.lua — `gs` writes what the zen window shows to a PNG next to the
-- original, `gy` copies it to the clipboard as an image; both cut from the original at full
-- resolution, at any depth of the selection stack.
--
-- Real windows and geometry; the crop writes a real PNG of the cut size, the clipboard is
-- lib.nvim's `copy_image_to_clipboard` stood in for by a recorder.

---@param H table harness from TESTS/run.lua
return function(H)
  local stubbed = {
    "images.anchor",
    "images.terminal",
    "images.guard",
    "images.info",
    "images.convert",
    "lib.nvim.cross.executable",
    "lib.nvim.cross.copy_image_to_clipboard",
    "lib.nvim.notify",
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
  local crops = {}
  package.loaded["images.convert"] = {
    crop = function(src, spec, out, _, on_done)
      crops[#crops + 1] = { src = src, spec = spec, out = out }
      local w, h = spec:match("^(%d+)x(%d+)")
      vim.fn.mkdir(vim.fs.dirname(out), "p")
      local fd = assert(io.open(out, "wb"))
      fd:write(require("images.testcard").build(tonumber(w), tonumber(h)))
      fd:close()
      on_done(out, nil)
    end,
  }
  local has_magick = true
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function(bin)
      return bin == "magick" and has_magick
    end,
  }
  local copied = {}
  package.loaded["lib.nvim.cross.copy_image_to_clipboard"] = setmetatable({}, {
    __call = function(_, path, on_done)
      copied[#copied + 1] = path
      if on_done then on_done(true, nil) end
    end,
  })
  local infos = {}
  local real_notify = saved["lib.nvim.notify"] or require("lib.nvim.notify")
  package.loaded["lib.nvim.notify"] = setmetatable({
    create = function(...)
      local n = real_notify.create(...)
      return setmetatable({
        info = function(msg)
          infos[#infos + 1] = msg
        end,
        warn = function(msg)
          infos[#infos + 1] = "warn: " .. msg
        end,
      }, { __index = n })
    end,
  }, { __index = real_notify })
  package.loaded["images.zen"] = nil
  local zen = require("images.zen")
  local vp = require("images.viewport")

  local function settle()
    vim.wait(20, function()
      return false
    end, 5)
  end
  local zen_cfg = require("images.config").get().display.zen
  local saved_save = vim.deepcopy(zen_cfg.save)

  H.tmpdir(function(dir)
    local file = dir .. "/shot.png"
    local fd = assert(io.open(file, "wb"))
    fd:write(require("images.testcard").build(600, 300))
    fd:close()

    H.ok(zen.open(file), "zen opens")
    settle()

    -- ── The whole original: nothing to save, the file itself to copy ─────
    H.falsy(zen.save(), "gs on the whole original saves nothing")
    H.ok(tostring(infos[#infos]):find("whole original", 1, true) ~= nil, "... and says that is the original")
    H.eq(#crops, 0, "... without cutting")
    H.ok(zen.yank(), "gy on the whole original")
    H.eq(copied[#copied], file, "... copies the PNG itself")
    H.eq(#crops, 0, "... without cutting")

    -- ── Zoomed: the visible part, from the original ──────────────────────
    zen.zoom(2)
    settle()
    local before = #crops
    H.ok(zen.save(), "gs on a zoomed view")
    local cut = crops[#crops]
    H.eq(cut.src, file, "it is cut from the original")
    H.eq(cut.spec, "300x150+150+75", "exactly the visible rectangle")
    local target = dir .. "/shot.crop-150-75-300x150.png"
    H.eq(cut.out, target, "written next to the original, named after the rectangle")
    H.ok(vim.uv.fs_stat(target) ~= nil, "the file exists")
    H.ok(tostring(infos[#infos]):find(target, 1, true) ~= nil, "the message names the file")

    zen.save()
    H.eq(crops[#crops].out, dir .. "/shot.crop-150-75-300x150-2.png", "a second save never overwrites: -2")
    H.eq(#crops, before + 2, "two cuts")

    -- save.dir
    zen_cfg.save = { dir = dir .. "/parts" }
    zen.save()
    H.eq(crops[#crops].out, dir .. "/parts/shot.crop-150-75-300x150.png", "save.dir puts it there")
    -- save.ask: the name is offered, an existing one is refused
    local real_input = vim.ui.input
    local offered
    vim.ui.input = function(opts, cb)
      offered = opts.default
      cb(dir .. "/named.png")
    end
    zen_cfg.save = { ask = true }
    zen.save()
    H.eq(offered, dir .. "/shot.crop-150-75-300x150-3.png", "ask offers the free default name")
    H.eq(crops[#crops].out, dir .. "/named.png", "and writes the name given")
    local n = #crops
    zen.save()
    H.eq(#crops, n, "a name that exists is not overwritten")
    H.ok(tostring(infos[#infos]):find("not overwritten", 1, true) ~= nil, "... and says so")
    vim.ui.input = real_input
    zen_cfg.save = vim.deepcopy(saved_save)

    -- ── gy on a zoomed view: cut into the cache, copied, cached ──────────
    n = #crops
    H.ok(zen.yank(), "gy on a zoomed view")
    H.eq(#crops, n + 1, "it is cut")
    H.eq(crops[#crops].spec, "300x150+150+75", "... the visible rectangle")
    H.eq(copied[#copied], crops[#crops].out, "and that file goes to the clipboard")
    H.ok(crops[#crops].out:find("yank%-") ~= nil, "a cache file, not one next to the original")
    zen.yank()
    H.eq(#crops, n + 1, "the same rectangle again: from the cache, no second cut")

    -- ── In a selection: the original at the selection's offset ───────────
    zen.zoom_reset()
    settle()
    zen.open_selection(nil, { x = 100, y = 50, w = 200, h = 100 })
    settle()
    H.eq(zen.origin().x, 100, "a selection window sits at 100,50 of the original")
    H.ok(zen.save(), "gs in a selection at its whole: it is a part, so it is saved")
    H.eq(crops[#crops].src, file, "cut from the original")
    H.eq(crops[#crops].spec, "200x100+100+50", "at the selection's offset")
    zen.zoom(2)
    settle()
    zen.save()
    local r = zen.viewport()
    H.eq(
      crops[#crops].spec,
      vp.geometry({ x = 100 + r.x, y = 50 + r.y, w = r.w, h = r.h }),
      "zoomed inside the selection: offset plus the visible rectangle"
    )

    -- ── Without ImageMagick nothing is cut ───────────────────────────────
    has_magick = false
    n = #crops
    H.falsy(zen.save(), "no magick: no save")
    H.falsy(zen.yank(), "no magick: no copy of a part")
    H.eq(#crops, n, "nothing was cut")
    has_magick = true
    zen.close()

    -- save_target is pure apart from looking for existing files
    H.eq(
      zen.save_target(dir .. "/a.jpg", { x = 1, y = 2, w = 3, h = 4 }, nil),
      dir .. "/a.crop-1-2-3x4.png",
      "save_target: always a PNG next to the original"
    )
  end)

  zen_cfg.save = saved_save
  for _, name in ipairs(stubbed) do
    package.loaded[name] = saved[name]
  end
end
