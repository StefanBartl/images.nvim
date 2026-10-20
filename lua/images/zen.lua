---@module 'images.zen'
---@brief Full-screen display for a single image.
---@description
--- Unlike `images.show` (a short block below the cursor) this fills nearly the
--- whole editor. Deliberately an ordinary, editable window plus buffer via
--- `lib.nvim.window.make_scratch` — NOT `ui.kit.viewer`, which is
--- read-only and closes itself on losing focus. That auto-close behaviour is
--- precisely what is unwanted here: a snacks hover popup opens its own float
--- beside or over this one, and a window tied to focus loss would vanish the
--- moment it did. An ordinary window has no such lifecycle and stays put, no
--- matter what pops up next to it.
---
--- The image itself remains a terminal overlay, as everywhere in images.nvim
--- (see `images.terminal`) — the window only supplies the target coordinates,
--- via window geometry rather than cursor position.
---
--- **A zen window can show part of its image.** `+`/`-` zoom, `hjkl` move the
--- visible rectangle (`images.viewport` does the arithmetic). OSC 1337 has no
--- source rectangle, so a zoomed view is a file: `images.convert.crop` cuts it
--- (~250 ms for a 1080p screenshot on Windows), the result is cached per
--- rectangle, and at most one `magick` runs per window -- when it finishes, the
--- rectangle the user has arrived at by then is the one drawn next ("latest
--- wins"), so holding a key never queues a backlog of crops. The crop is not
--- resized: its pixel size is what `images.anchor` fits the draw box against,
--- and a crop is never larger than its source anyway.
---
--- State is kept per window (`views`), not in module globals, so a later
--- child window (a selection opened as its own zen) has somewhere to live.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- A configured fraction, made safe to multiply against `vim.o.columns`/
--- `vim.o.lines` below (ERR-22): a non-number `width`/`height` throws there
--- ("attempt to perform arithmetic on a ... value", reproduced with a string,
--- a boolean and a table) since `zen_cfg.width or 0.9` only substitutes the
--- default on `nil`/`false`, not on a wrong type. 0 and negative fractions
--- are left to `M.dimensions`'s own `math.max(1, ...)` clamp, same as before.
---@param value any
---@param default number
---@return number
local function valid_fraction(value, default)
  if type(value) == "number" and value == value then return value end
  return default
end

---@class ImagesNvim.ZenView
---@field win integer
---@field buf integer
---@field file string the image as opened
---@field box { width: number, height: number } fractions the window was sized from; what `M.resize` steps away from
---@field px Images.Scale.Dims|nil pixel size of `file`, nil when its header does not say (no zoom then)
---@field rect Images.Viewport.Rect|nil the visible rectangle; nil without `px`
---@field queued string|nil the file a deferred draw is queued for, until it has settled
---@field cropping boolean a `magick` crop for this view is running
---@field broken boolean a crop failed: zoom is off for this window
---@field title string|nil the title on the frame now
---@field footer string|nil the footer on the frame now
---@field depth integer|nil 1 for a window opened on a file; a selection opened from one is one deeper
---@field help integer|nil the cheatsheet window while it is open (no drawing then)
---@field drag ImagesNvim.ZenDrag|nil a middle-button drag in progress
---@field select ImagesNvim.ZenSelect|nil a selection in progress
---@field winhl string|nil the window's 'winhighlight' before the selection coloured the frame
---@field parent ImagesNvim.ZenView|nil the window this one's picture was cut from
---@field origin ImagesNvim.ZenOrigin where this window's file sits in the original
---@field hidden boolean|nil hidden under a selection opened from it

--- Every open zen window, by window id.
---@type table<integer, ImagesNvim.ZenView>
local views = {}

--- The zen window `M.resize`/`M.is_open` mean when called from outside one.
---@type integer|nil
local current = nil

--- The size steps `M.resize` cycles through when the user configured none.
---@type { width: number, height: number }[]
local DEFAULT_SIZES = {
  { width = 0.66, height = 0.66 },
  { width = 0.9, height = 0.85 },
  { width = 1, height = 1 },
}

---@param view ImagesNvim.ZenView|nil
---@return boolean
local function alive(view)
  return view ~= nil and views[view.win] == view and vim.api.nvim_win_is_valid(view.win)
end

--- The view the user is acting on: the zen window they are in, else the one
--- opened last.
---@return ImagesNvim.ZenView|nil
local function active()
  local here = views[vim.api.nvim_get_current_win()]
  if alive(here) then return here end
  local last = current and views[current]
  if alive(last) then return last end
  return nil
end

-- ── Crops ──────────────────────────────────────────────────────────────────

--- Cropped views already on disk, keyed by file, mtime and rectangle; swept at
--- exit. Stepping back to a rectangle already seen costs no second `magick`.
---@type table<string, string>
local crops = {}

local cleanup_armed = false

---@return string
local function crop_dir()
  return vim.fn.stdpath("cache") .. "/images.nvim/zoom"
end

--- Seconds after which a crop found on disk from an earlier session is
--- deleted. Not every crop reaches the exit sweep (a crashed session leaves
--- its own behind); an hour leaves another running instance's fresh ones alone.
local STALE_S = 60 * 60

--- Delete leftovers older than `STALE_S` from the crop directory.
local function sweep_stale()
  local dir = crop_dir()
  local now = os.time()
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%.png$") then
      local path = dir .. "/" .. name
      local st = vim.uv.fs_stat(path)
      if st and st.mtime and now - st.mtime.sec > STALE_S then pcall(vim.uv.fs_unlink, path) end
    end
  end
end

local function arm_cleanup()
  if cleanup_armed then return end
  cleanup_armed = true
  pcall(sweep_stale)
  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("VimLeavePre", function()
    for _, path in pairs(crops) do
      pcall(vim.uv.fs_unlink, path)
    end
    crops = {}
  end, {
    group = autocmd.group("images.zen.crops", true),
    desc = "images.zen: delete the cropped views at exit",
  })
end

---@param file string
---@param rect Images.Viewport.Rect
---@return string|nil
local function crop_key(file, rect)
  local st = vim.uv.fs_stat(file)
  if not st then return nil end
  return table.concat({ file, tostring(st.mtime and st.mtime.sec or 0), require("images.viewport").geometry(rect) }, "\0")
end

-- ── Legend ─────────────────────────────────────────────────────────────────

--- Narrower than this, the footer is only `?`.
local FOOTER_MIN_WIDTH = 30

---@return boolean
local function legend_on()
  return (cfg().display.zen or {}).legend ~= false
end

--- The keys bound to `help` in `view`'s buffer, from the keymap registry: what
--- the footer advertises and what closes the list again.
---@param view ImagesNvim.ZenView|nil
---@return string[]
function M.help_keys(view)
  view = view or active()
  local out = {}
  if not view then return out end
  for _, e in ipairs(require("lib.nvim.bindings.keymap").registered("images/zen")) do
    if e.name == "help" and e.bound and e.lhs and e.buffer == view.buf then out[#out + 1] = e.lhs end
  end
  return out
end

--- The zoom factor as the title shows it: `2.3×`, `2×`; nil at the whole picture.
---@param view ImagesNvim.ZenView
---@return string|nil
local function zoom_label(view)
  if not (view.px and view.rect) then return nil end
  local vp = require("images.viewport")
  if vp.is_full(view.px, view.rect) then return nil end
  local text = ("%.1f"):format(vp.factor(view.px, view.rect)):gsub("%.0$", "")
  return text .. "×"
end

--- The frame's title and footer for `view` (default: the active zen window)
--- right now. Pure apart from reading the window's width.
---@param view ImagesNvim.ZenView|nil
---@return string|nil title nil without a zen window
---@return string|nil footer nil without a legend
function M.legend(view)
  view = view or active()
  if not view then return nil, nil end
  -- The original's name: a selection's file is a crop in the cache (`sel-<hash>.png`).
  local parts = { vim.fn.fnamemodify((view.origin and view.origin.file) or view.file, ":t") }
  if not legend_on() then return " " .. parts[1] .. " ", nil end
  parts[#parts + 1] = zoom_label(view)
  if (view.depth or 1) > 1 then
    local deepest = 1
    for _, other in pairs(views) do
      deepest = math.max(deepest, other.depth or 1)
    end
    parts[#parts + 1] = ("%d/%d"):format(view.depth, deepest)
  end
  -- The footer names the key that really opens the list, and is left off
  -- when none does: advertising `?` after `keys.help = false` would be a lie.
  local key = M.help_keys(view)[1]
  local footer = nil
  if key then
    local width = vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_width(view.win) or 0
    footer = width < FOOTER_MIN_WIDTH and (" " .. key .. " ") or (" " .. key .. " help ")
  end
  return " " .. table.concat(parts, " · ") .. " ", footer
end

--- Put the legend on the frame when it differs from what is there. Only ever
--- called right before a draw (see `draw`).
---@param view ImagesNvim.ZenView
---@return nil
local function update_legend(view)
  local title, footer = M.legend(view)
  if title == view.title and footer == view.footer then return end
  local printable = require("lib.nvim.window.printable_title")
  local config = { title = printable(title), title_pos = "center" }
  if footer then
    config.footer = printable(footer)
    config.footer_pos = "right"
  elseif view.footer then
    config.footer = ""
  end
  if pcall(vim.api.nvim_win_set_config, view.win, config) then
    view.title, view.footer = title, footer
  end
end

-- ── Drawing ────────────────────────────────────────────────────────────────

--- Draw `path` into `view`'s window at its current geometry. `defer = true`
--- because on the first call the window has only just been opened — see
--- `images.anchor`'s module docs for the reasoning.
---
--- At most one draw of the same file is queued per window: `M.resize`
--- redraws, and the `WinResized` its own size change fires asks again before
--- the queued draw has run. That second call would send the whole picture to
--- the terminal a second time for the same geometry; the queued draw reads the
--- geometry when it runs, so skipping it loses nothing. A draw of a DIFFERENT
--- file is never skipped: the queued one carries its file with it, and a quick
--- zoom out and back in within one tick would otherwise leave the whole
--- picture on screen under a zoomed rectangle. Both run, in order, and the
--- later one is what stays.
---@param view ImagesNvim.ZenView
---@param path string
---@return nil
local function draw(view, path)
  if not alive(view) or view.help or view.hidden then return end
  -- The legend changes here and nowhere else, so every change of the frame is
  -- followed by a draw: `nvim_win_set_config` makes WezTerm drop the picture
  -- (measured 2026-10-20), and the queued draw puts it back.
  update_legend(view)
  if view.queued == path then return end
  view.queued = path
  require("images.anchor").draw(view.win, "full", path, {
    defer = true,
    -- The key list may have opened, or the window gone, between this request
    -- and the tick the draw runs in (`+?` typed fast, a macro): the picture
    -- would then land on top of the list.
    skip_if = function()
      return not alive(view) or view.help ~= nil or view.hidden == true
    end,
    on_done = function(ok, err)
      if view.queued == path then view.queued = nil end
      -- A deferred draw whose window was closed in the meantime (`q` right
      -- after a resize) has nothing left to draw into: not an error.
      if ok or not alive(view) then return end
      notify().error(err or "could not display the image")
    end,
  })
  -- Queued after anchor's own deferred draw (vim.schedule is FIFO): releases
  -- the slot even when that draw raised and never reached on_done.
  vim.schedule(function()
    if view.queued == path then view.queued = nil end
  end)
end

--- Show `view.rect` of the image: the file itself when the whole picture is
--- visible, else its crop -- cut first if it is not on disk yet.
---@param view ImagesNvim.ZenView
---@return nil
local function show(view)
  if not alive(view) then return end
  local vp = require("images.viewport")
  if not (view.px and view.rect) or vp.is_full(view.px, view.rect) then return draw(view, view.file) end

  local rect = view.rect
  local key = crop_key(view.file, rect)
  local cached = key and crops[key]
  if cached and vim.uv.fs_stat(cached) then return draw(view, cached) end
  -- Latest wins: the running crop calls back into here, and reads the rectangle
  -- the user has arrived at by then.
  if view.cropping then return end

  view.cropping = true
  local out = ("%s/%s.png"):format(crop_dir(), vim.fn.sha256(key or view.file))
  require("images.convert").crop(view.file, vp.geometry(rect), out, nil, function(path, err)
    view.cropping = false
    -- Recorded before anything else, so a crop finishing after its window
    -- closed is still swept at exit rather than left on disk.
    if path and key then
      crops[key] = path
      arm_cleanup()
    end
    if not alive(view) then return end
    if not path then
      -- One failure ends zoom for this window (an animated GIF, for one:
      -- `magick` writes a file per frame and none under the name asked for).
      -- Retrying on every key would start a `magick` and an error per press,
      -- and the view goes back to what is really on screen.
      view.broken = true
      view.rect = view.px and vp.full(view.px) or nil
      -- A drag in progress would put its zoomed rectangle back on the next
      -- move, and with it a `magick` and an error per event.
      view.drag = nil
      notify().error((err or "could not cut the zoomed view") .. " -- zoom is off for this window")
      return draw(view, view.file)
    end
    show(view)
  end)
end

-- ── Size ───────────────────────────────────────────────────────────────────

--- Compute the window size from the configured fractions. A pure function (no
--- window, no side effects) and therefore testable without a terminal, unlike
--- the rest of this module. This is the MAXIMUM box; `M.dimensions_for`
--- shrinks it to an image's aspect ratio where needed.
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return integer width
---@return integer height
function M.dimensions(zen_cfg)
  zen_cfg = zen_cfg or {}
  local width = math.max(1, math.floor(vim.o.columns * valid_fraction(zen_cfg.width, 0.9)))
  local height = math.max(1, math.floor(vim.o.lines * valid_fraction(zen_cfg.height, 0.85)))
  return width, height
end

--- Window size for ONE specific image: the maximum box from `M.dimensions`,
--- shrunk to the image's aspect ratio (`images.scale.fit_cells`, the same
--- function `images.redact` already uses for this). Without real pixel
--- dimensions (no ImageMagick, or a format `images.info` cannot read) the
--- maximum box stands — unchanged behaviour.
---
--- Why do this here rather than let `preserveAspectRatio=1` handle it alone:
--- a window wider or taller than the (scaled) image shows visible empty space,
--- and a window cut to fit never has to leave anything empty in the first
--- place. The stronger reason came later — a terminal handed a box the picture
--- cannot fill scales to the WIDTH and lets the height run past the box, which
--- past the last row scrolls the screen. `images.anchor` now fits the draw box
--- the same way for every caller, so this is belt and braces rather than the
--- only line of defence; shaping the window is still worth it, because an
--- empty strip inside a frame is a frame in the wrong shape.
---@param file string
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return integer width
---@return integer height
function M.dimensions_for(file, zen_cfg)
  local max_w, max_h = M.dimensions(zen_cfg)
  local px = require("images.info").collect(file)
  if not px or not px.width or not px.height then return max_w, max_h end
  return require("images.scale").fit_cells(max_w, max_h, px)
end

--- The configured size steps, without invalid entries; the defaults when none
--- is left.
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return { width: number, height: number }[]
local function valid_sizes(zen_cfg)
  local out = {}
  local sizes = zen_cfg and zen_cfg.sizes
  if type(sizes) == "table" then
    for _, s in ipairs(sizes) do
      if type(s) == "table" and type(s.width) == "number" and type(s.height) == "number" then
        out[#out + 1] = { width = s.width, height = s.height }
      end
    end
  end
  return #out > 0 and out or DEFAULT_SIZES
end

--- The size step after `box` in direction `dir`: the smallest step with a
--- larger area for `dir > 0`, the largest one with a smaller area for
--- `dir < 0`; nil when there is none. The steps need not be sorted, and `box`
--- need not be one of them (the window may have opened at a size of its own).
--- Pure, like `M.dimensions`.
---@param box { width: number, height: number }
---@param sizes { width: number, height: number }[]
---@param dir integer
---@return { width: number, height: number }|nil
function M.next_size(box, sizes, dir)
  local area = box.width * box.height
  local best, best_area
  for _, s in ipairs(sizes) do
    local a = s.width * s.height
    if dir > 0 and a > area + 1e-9 and (not best_area or a < best_area) then
      best, best_area = s, a
    elseif dir < 0 and a < area - 1e-9 and (not best_area or a > best_area) then
      best, best_area = s, a
    end
  end
  return best
end

--- Grow (`dir > 0`) or shrink (`dir < 0`) the open zen window to the next size
--- step (`display.zen.sizes`), re-centred, and draw the image again at the new
--- size. A no-op without an open window or at the last step in that direction.
---@param dir integer
---@return boolean changed
function M.resize(dir)
  local view = active()
  if not view then return false end
  -- The drag's picture box is the old window's; it would map the pointer wrongly.
  view.drag = nil
  local box = M.next_size(view.box, valid_sizes(cfg().display.zen), dir)
  if not box then return false end
  local width, height = M.dimensions_for(view.file, box)
  -- The same caps `lib.nvim.window.make_scratch` applies on open, so the
  -- full-screen step still leaves the border and the command line visible.
  width = math.min(width, require("lib.nvim.window.max_float_width")())
  height = math.min(height, math.max(1, vim.o.lines - 4))
  if not pcall(vim.api.nvim_win_set_config, view.win, { width = width, height = height }) then return false end
  view.box = box
  require("lib.nvim.window.center")(view.win)
  -- The previous, larger picture is still on the terminal around the window.
  require("images.terminal").clear()
  show(view)
  return true
end

-- ── Zoom and pan ───────────────────────────────────────────────────────────

--- Reasons already reported this session, so holding `+` on an image that
--- cannot be zoomed says so once.
---@type table<string, true>
local told = {}

---@param reason string
local function tell_once(reason)
  if told[reason] then return end
  told[reason] = true
  notify().warn(reason)
end

--- Whether `view` can show anything but the whole picture; says why not, once.
---@param view ImagesNvim.ZenView
---@return boolean
local function zoomable(view)
  if view.broken then return false end
  if not (view.px and view.rect) then
    tell_once("zoom: this image does not say how large it is")
    return false
  end
  if not require("lib.nvim.cross.executable").exists("magick") then
    tell_once("zoom needs ImageMagick (magick) on PATH")
    return false
  end
  return true
end

---@param view ImagesNvim.ZenView
---@param rect Images.Viewport.Rect
---@return boolean changed
local function move_to(view, rect, by_drag)
  -- Anything but the drag itself that moves the view ends a drag in progress:
  -- the drag pans from the rectangle it started on, and would otherwise undo
  -- a zoom made with the button still held on its next event.
  if not by_drag then view.drag = nil end
  if rect == view.rect then return false end
  -- A selection is measured against the view it started on; once that moves
  -- it would cut something other than what was marked.
  if view.select then M.select_cancel() end
  view.rect = rect
  show(view)
  return true
end

--- Zoom the active zen window by `factor` (> 1 in, < 1 out) around the point
--- `fx`,`fy` of the visible rectangle (fractions 0..1, default the centre).
---@param factor number
---@param fx number|nil
---@param fy number|nil
---@return boolean changed
function M.zoom(factor, fx, fy)
  local view = active()
  if not view or not zoomable(view) then return false end
  local vp = require("images.viewport")
  return move_to(view, vp.zoom_at(view.px, view.rect, factor, fx, fy))
end

--- Back to the whole picture.
---@return boolean changed
function M.zoom_reset()
  local view = active()
  if not (view and view.px and view.rect) then return false end
  local vp = require("images.viewport")
  if vp.is_full(view.px, view.rect) then return false end
  return move_to(view, vp.full(view.px))
end

--- Move the visible rectangle by `fx`,`fy` of its own size (`math.huge` = to
--- the edge). Nothing to move while the whole picture is visible.
---@param fx number
---@param fy number
---@return boolean changed
function M.pan(fx, fy)
  local view = active()
  if not (view and view.px and view.rect) then return false end
  return move_to(view, require("images.viewport").pan_by(view.px, view.rect, fx, fy))
end

-- ── Mouse ──────────────────────────────────────────────────────────────────
--
-- The functions take SCREEN cells (1-based, as `getmousepos()` reports them),
-- so the mappings below only read the mouse and everything else is testable
-- headless, where `nvim_input_mouse` fires no mappings.

---@class ImagesNvim.ZenDrag
---@field row integer screen row the drag started on
---@field col integer
---@field rect Images.Viewport.Rect the visible rectangle when it started
---@field box Images.Viewport.Box the picture box when it started

---@param view ImagesNvim.ZenView
---@return Images.Viewport.Box box the cells the picture covers, relative to the content
---@return integer row0 screen row of the window's first content cell
---@return integer col0
local function picture_box(view)
  local anchor = require("images.anchor")
  local row0, col0 = anchor.content_origin(view.win)
  local box = require("images.viewport").image_box(
    vim.api.nvim_win_get_width(view.win),
    vim.api.nvim_win_get_height(view.win),
    anchor.inset(),
    view.rect
  )
  return box, row0, col0
end

--- Zoom by `factor` around the picture point under the screen cell
--- `screenrow`,`screencol`; around the centre when that cell is not on the
--- picture (the margin, the border).
---@param factor number
---@param screenrow integer
---@param screencol integer
---@return boolean changed
function M.zoom_at_screen(factor, screenrow, screencol)
  local view = active()
  if not view or not zoomable(view) then return false end
  local box, row0, col0 = picture_box(view)
  local fx, fy, inside = require("images.viewport").fraction_at(box, screenrow - row0 + 1, screencol - col0 + 1)
  if not inside then
    fx, fy = 0.5, 0.5
  end
  return M.zoom(factor, fx, fy)
end

--- Start a drag at a screen cell. Nothing to drag while the whole picture is
--- visible, or without a known size.
---@param screenrow integer
---@param screencol integer
---@return boolean started
function M.drag_begin(screenrow, screencol)
  local view = active()
  if not (view and view.px and view.rect) then return false end
  local box = picture_box(view)
  view.drag = { row = screenrow, col = screencol, rect = view.rect, box = box }
  return true
end

--- Continue the drag to a screen cell: the picture follows the pointer, cell
--- for cell, measured from where the drag began (not step by step, so rounding
--- never accumulates). Latest wins applies as for every move: a crop in flight
--- is followed by the rectangle the pointer has reached by then.
---@param screenrow integer
---@param screencol integer
---@return boolean changed
function M.drag_to(screenrow, screencol)
  local view = active()
  local drag = view and view.drag
  if not drag or view.broken then return false end
  local vp = require("images.viewport")
  if vp.is_full(view.px, drag.rect) then return false end
  return move_to(view, vp.drag(view.px, drag.rect, drag.box, screencol - drag.col, screenrow - drag.row), true)
end

--- End the drag at a screen cell.
---@param screenrow integer
---@param screencol integer
---@return boolean changed
function M.drag_end(screenrow, screencol)
  local changed = M.drag_to(screenrow, screencol)
  local view = active()
  if view then view.drag = nil end
  return changed
end

--- The mouse position, and whether it is over `view`'s window. `getmousepos()`
--- names the window under the pointer reliably here: the zen float is
--- focusable (a non-focusable float is what that field cannot see).
---@param view ImagesNvim.ZenView|nil
---@return table|nil pos
---@return boolean over
local function mouse(view)
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or type(pos) ~= "table" then return nil, false end
  return pos, view ~= nil and pos.winid == view.win
end

---@param factor_of_step fun(step: number): number
---@return fun()
local function wheel_rhs(factor_of_step)
  return function()
    local view = active()
    local pos, over = mouse(view)
    -- A wheel points: it acts on what it is aimed at, and not at all elsewhere.
    if not (pos and over) then return end
    M.zoom_at_screen(factor_of_step(require("images.viewport").ZOOM_STEP), pos.screenrow, pos.screencol)
  end
end

--- The visible rectangle of the active zen window, and the pixel size of its
--- image; nil without an open window or known dimensions. For tests and the
--- legend.
---@return Images.Viewport.Rect|nil rect
---@return Images.Scale.Dims|nil px
function M.viewport()
  local view = active()
  if not view then return nil end
  return view.rect, view.px
end

-- ── Cheatsheet ─────────────────────────────────────────────────────────────

--- How `?` groups the zen keys. Built from the registry, so what it lists is
--- what is bound in this window: a remapped key shows its new key, a disabled
--- one is absent.
---@type Lib.Keymap.CheatsheetGroup[]
local HELP_GROUPS = {
  { title = "Zoom", actions = { "zoom_in", "zoom_out", "zoom_reset" } },
  {
    title = "Move",
    actions = { "pan_left", "pan_right", "pan_up", "pan_down", "edge_left", "edge_right", "edge_up", "edge_down" },
  },
  { title = "Mouse", actions = { "wheel_in", "wheel_out", "drag" } },
  { title = "Select", actions = { "select_drag", "select", "back" } },
  { title = "Window", actions = { "grow", "shrink", "help" } },
}

---@param view ImagesNvim.ZenView
local function close_help(view)
  if view.help and vim.api.nvim_win_is_valid(view.help) then pcall(vim.api.nvim_win_close, view.help, true) end
end

--- The cheatsheet of `view` (default: the active zen window), as
--- `lib.nvim.bindings.keymap.cheatsheet` builds it.
---@param view ImagesNvim.ZenView|nil
---@return Lib.Keymap.Cheatsheet|nil
function M.cheatsheet(view)
  view = view or active()
  if not view then return nil end
  local close = vim.list_extend(vim.deepcopy(M.help_keys(view)), { "q", "<Esc>" })
  local footer = {
    table.concat(close, " / ") .. "   close this list",
    "q / <Esc> in the picture   close the zen window",
  }
  if not require("lib.nvim.cross.executable").exists("magick") then
    footer[#footer + 1] = "zoom needs ImageMagick (magick), which is not on PATH"
  end
  return require("lib.nvim.bindings.keymap").cheatsheet("images/zen", {
    buffer = view.buf,
    groups = HELP_GROUPS,
    footer = footer,
  })
end

--- Toggle the list of the zen window's keys. While it is open the picture is
--- taken off the screen -- an OSC 1337 image would sit on top of the list, and
--- nothing removes one picture but a full repaint -- and drawn again when the
--- list closes.
---@return boolean shown
function M.help()
  local view = active()
  if not view then return false end
  if view.help and vim.api.nvim_win_is_valid(view.help) then
    close_help(view)
    return false
  end

  local sheet = M.cheatsheet(view) --[[@as Lib.Keymap.Cheatsheet]]
  require("images.terminal").clear()
  local win, buf = require("lib.nvim.window.make_scratch")({
    lines = sheet.lines,
    title = " images: zen keys ",
    title_pos = "center",
    nice_quit = true,
    zindex = 60,
  })
  if not win or not buf then
    show(view)
    return false
  end
  view.help = win

  local ns = vim.api.nvim_create_namespace("images.zen.help")
  for _, h in ipairs(sheet.highlights) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.line, h.col_start, { end_col = h.col_end, hl_group = h.group })
  end
  -- The key that opened the list closes it too, whatever it is bound to.
  for _, lhs in ipairs(M.help_keys(view)) do
    require("lib.nvim.bindings.keymap")("n", lhs, function()
      close_help(view)
    end, { buffer = buf, nowait = true }, "images: close the zen key list")
  end

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    view.help = nil
    if not alive(view) then return end
    pcall(vim.api.nvim_set_current_win, view.win)
    show(view)
  end, {
    group = autocmd.group("images.zen.help", true),
    pattern = tostring(win),
    once = true,
    desc = "images.zen: draw the picture again when the key list closes",
  })
  return true
end

-- ── Keys ───────────────────────────────────────────────────────────────────

--- A pan step: a quarter of the visible rectangle per press, times the count.
local PAN_STEP = 0.25

--- Cells a keyboard selection's corner moves per H/J/K/L (h/j/k/l: one).
local SELECT_BIG_STEP = 5

---@param fx number
---@param fy number
---@return fun()
local function pan_rhs(fx, fy)
  return function()
    local n = vim.v.count1
    -- In a keyboard selection the same keys move its second corner instead:
    -- one cell, or five for the H/J/K/L "edge" keys, times the count.
    local function cells(f)
      if f == 0 then return 0 end
      local step = (f == math.huge or f == -math.huge) and SELECT_BIG_STEP or 1
      return (f > 0 and step or -step) * n
    end
    if M.select_step(cells(fy), cells(fx)) then return end
    local function scaled(f)
      if f == math.huge or f == -math.huge then return f end
      return f * n
    end
    M.pan(scaled(fx), scaled(fy))
  end
end

--- The zen window's actions. Their default keys are `display.zen.keys` in
--- `images.config.DEFAULTS`, read from there so the two cannot disagree.
---@type table<string, Lib.Keymap.Action>
local ACTIONS = {
  grow = {
    desc = "grow the window",
    rhs = function()
      M.resize(1)
    end,
  },
  shrink = {
    desc = "shrink the window",
    rhs = function()
      M.resize(-1)
    end,
  },
  zoom_in = {
    desc = "zoom in (a count: that many steps)",
    rhs = function()
      M.zoom(require("images.viewport").ZOOM_STEP ^ vim.v.count1)
    end,
  },
  zoom_out = {
    desc = "zoom out",
    rhs = function()
      M.zoom(1 / require("images.viewport").ZOOM_STEP ^ vim.v.count1)
    end,
  },
  zoom_reset = {
    desc = "the whole picture",
    rhs = function()
      M.zoom_reset()
    end,
  },
  pan_left = { desc = "move the view left a quarter", rhs = pan_rhs(-PAN_STEP, 0) },
  pan_right = { desc = "move the view right a quarter", rhs = pan_rhs(PAN_STEP, 0) },
  pan_up = { desc = "move the view up a quarter", rhs = pan_rhs(0, -PAN_STEP) },
  pan_down = { desc = "move the view down a quarter", rhs = pan_rhs(0, PAN_STEP) },
  edge_left = { desc = "move the view to the left edge", rhs = pan_rhs(-math.huge, 0) },
  edge_right = { desc = "move the view to the right edge", rhs = pan_rhs(math.huge, 0) },
  edge_up = { desc = "move the view to the top edge", rhs = pan_rhs(0, -math.huge) },
  edge_down = { desc = "move the view to the bottom edge", rhs = pan_rhs(0, math.huge) },
  help = {
    desc = "this list of keys",
    rhs = function()
      M.help()
    end,
  },
  wheel_in = {
    desc = "Alt + wheel up: zoom in at the pointer",
    rhs = wheel_rhs(function(step)
      return step
    end),
  },
  wheel_out = {
    desc = "Alt + wheel down: zoom out at the pointer",
    rhs = wheel_rhs(function(step)
      return 1 / step
    end),
  },
  select = {
    desc = "select a part by keyboard (hjkl move the corner, <CR> opens, <Esc> drops)",
    rhs = function()
      M.select_keys()
    end,
  },
  select_drag = {
    desc = "drag with the left button: open that part in its own window",
    rhs = function() end, -- bound per variant in `map_fixed_keys`
  },
  back = {
    desc = "back to the window this part was cut from",
    rhs = function()
      M.back()
    end,
  },
  drag = {
    desc = "hold the middle button and drag: move the picture",
    rhs = function()
      local view = active()
      -- Every press ends the drag before it, over the window or not: a release
      -- that never arrived (the key list opened mid-drag, Alt let go first on
      -- an <M-LeftMouse> remap) must not let a later press elsewhere resume it.
      if view then view.drag = nil end
      local pos, over = mouse(view)
      if pos and over then M.drag_begin(pos.screenrow, pos.screencol) end
    end,
  },
}

---@type string[]
local ORDER = {
  "grow",
  "shrink",
  "zoom_in",
  "zoom_out",
  "zoom_reset",
  "pan_left",
  "pan_right",
  "pan_up",
  "pan_down",
  "edge_left",
  "edge_right",
  "edge_up",
  "edge_down",
  "help",
  "select",
  "select_drag",
  "back",
  "wheel_in",
  "wheel_out",
  "drag",
}

--- The press, drag and release keys of a drag key, plain and as 2- to 4-clicks:
--- `<M-LeftMouse>` gives `<M-LeftMouse>`/`<M-LeftDrag>`/`<M-LeftRelease>` and
--- `<M-2-LeftMouse>`/... (Neovim writes modifiers before the click count).
--- Empty for a key that does not end in `Mouse>` (any case).
---@param lhs string
---@return { press: string, drag: string, release: string }[]
local function drag_variants(lhs)
  local inner = lhs:match("^<(.*)>$")
  if not inner or inner:sub(-5):lower() ~= "mouse" then return {} end
  -- "Middle", "M-Left", "2-Middle", "2-M-Left": take the one-letter modifiers
  -- and a click count off the front, in whatever order they were written.
  local button, mods = inner:sub(1, -6), ""
  while true do
    local mod = button:match("^(%a%-)")
    local count = button:match("^(%d%-)")
    if mod then
      mods, button = mods .. mod, button:sub(3)
    elseif count then
      button = button:sub(3)
    else
      break
    end
  end
  local out = {}
  for _, count in ipairs({ "", "2-", "3-", "4-" }) do
    local base = "<" .. mods .. count .. button
    out[#out + 1] = { press = base .. "Mouse>", drag = base .. "Drag>", release = base .. "Release>" }
  end
  return out
end
M.drag_variants = drag_variants

---@param lhs string
---@return string the key as Neovim reads it, whatever its spelling
local function termcodes(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

local defaults_applied = false

--- Fill each action's `default` from `DEFAULTS` once: a `display.zen.keys`
--- that names only some actions (or an old config with just grow/shrink)
--- still binds the rest.
local function apply_defaults()
  if defaults_applied then return end
  defaults_applied = true
  local keys = require("images.config.DEFAULTS").display.zen.keys or {}
  for name, action in pairs(ACTIONS) do
    action.default = vim.deepcopy(keys[name])
    action.opts = { nowait = true }
  end
end

--- Bind the zen actions in `buf`. Through the keymap registry (surface `zen`,
--- so the markdown preset's record is not replaced), which is what lets a
--- cheatsheet list exactly what is bound. A pan key is bound even while the
--- whole picture is shown -- the zen buffer is empty, so `h` there moves
--- nothing anyway, and binding on zoom would mean rebinding on every step.
---@param buf integer
---@param keys table|false|nil `display.zen.keys`
---@return nil
local function map_keys(buf, keys)
  apply_defaults()
  -- `false` binds nothing; anything that is not a table means "the defaults".
  local user = nil
  if keys == false then
    user = false
  elseif type(keys) == "table" then
    user = keys
  end
  local keymap = require("lib.nvim.bindings.keymap")
  local bound = keymap.register("images", { actions = ACTIONS, order = ORDER }, user, { buffer = buf, surface = "zen" })

  -- A drag is three events, and only the first is the configurable key: the
  -- other two follow from it (`<MiddleMouse>` -> `<MiddleDrag>`,
  -- `<MiddleRelease>`; a `<M-LeftMouse>` remap gets `<M-LeftDrag>` ...).
  -- And each comes in multi-click variants: a press within 'mousetime' of the
  -- last one arrives as `<2-MiddleMouse>` (up to `<4-…>`) with `<2-MiddleDrag>`
  -- / `<2-MiddleRelease>` after it. Unbound, every second quick stroke of a
  -- long pan moved nothing and Neovim's own middle click pasted the register
  -- into the zen buffer instead.
  for _, e in ipairs(bound) do
    local variants = e.name == "drag" and e.bound and e.lhs and drag_variants(e.lhs) or {}
    for _, v in ipairs(variants) do
      -- Compared as keys, not as spellings: `<2-M-LeftMouse>` and
      -- `<M-2-LeftMouse>` are one key, and the registry already binds it.
      if termcodes(v.press) ~= termcodes(e.lhs) then
        keymap("n", v.press, ACTIONS.drag.rhs, { buffer = buf, nowait = true }, "images: zen: start dragging the picture")
      end
      keymap("n", v.drag, function()
        local pos = mouse(active())
        if pos then M.drag_to(pos.screenrow, pos.screencol) end
      end, { buffer = buf, nowait = true }, "images: zen: drag the picture")
      keymap("n", v.release, function()
        local pos = mouse(active())
        if pos then M.drag_end(pos.screenrow, pos.screencol) end
      end, { buffer = buf, nowait = true }, "images: zen: end the drag")
    end
  end
end

-- ── Open / close ───────────────────────────────────────────────────────────

--- Whether a zen window is currently open.
---@return boolean
function M.is_open()
  return active() ~= nil
end

-- Defined in the Selection section below; `open_view` needs both.
local end_select, map_fixed_keys

--- Set while `M.close` takes the whole stack down, so a closing child does not
--- bring its parent back for the moment before the parent closes too.
local closing_all = false

--- Close every zen window, the whole stack (a no-op when none is open).
---@return nil
function M.close()
  local any = false
  closing_all = true
  for win, view in pairs(views) do
    any = true
    views[win] = nil
    close_help(view)
    if vim.api.nvim_win_is_valid(view.win) then pcall(vim.api.nvim_win_close, view.win, true) end
  end
  closing_all = false
  current = nil
  if any then require("images.terminal").clear() end
end

--- Close the active zen window only: a selection goes back to the window it
--- was cut from, the first window closes the stack.
---@return boolean closed
function M.back()
  local view = active()
  if not view or not view.parent then return false end
  pcall(vim.api.nvim_win_close, view.win, true)
  return true
end

--- Bring `parent` back after its child closed: shown, focused, drawn.
---@param parent ImagesNvim.ZenView
local function restore(parent)
  if not alive(parent) then return end
  parent.hidden = false
  pcall(vim.api.nvim_win_set_config, parent.win, { hide = false })
  current = parent.win
  pcall(vim.api.nvim_set_current_win, parent.win)
  require("images.terminal").clear()
  show(parent)
end

---@class ImagesNvim.ZenOpenOpts
---@field width? number
---@field height? number
---@field parent? ImagesNvim.ZenView the window a selection was cut from
---@field origin? ImagesNvim.ZenOrigin where `file` sits in the original

--- Open a zen window on `file`. Without `opts.parent` every other zen window
--- is closed first; with one, the parent is hidden (keeping its view) and the
--- new window stacks on it.
---@param file string
---@param opts ImagesNvim.ZenOpenOpts
---@return boolean ok
local function open_view(file, opts)
  local zen_cfg = cfg().display.zen or {}
  local parent = opts.parent
  if not parent then M.close() end

  local box = parent and parent.box
    or {
      width = valid_fraction(opts.width, valid_fraction(zen_cfg.width, 0.9)),
      height = valid_fraction(opts.height, valid_fraction(zen_cfg.height, 0.85)),
    }
  local width, height = M.dimensions_for(file, box)

  if parent then
    parent.hidden = true
    parent.drag, parent.select = nil, nil
    pcall(vim.api.nvim_win_set_config, parent.win, { hide = true })
    require("images.terminal").clear()
  end

  local title = " " .. vim.fn.fnamemodify((opts.origin and opts.origin.file) or file, ":t") .. " "
  local win, buf = require("lib.nvim.window.make_scratch")({
    width = width,
    height = height,
    modifiable = true,
    title = title,
  })
  if not win or not buf then
    notify().error("could not open the zen window")
    if parent then restore(parent) end
    return false
  end

  local px = require("images.pixels").read(file)
  ---@type ImagesNvim.ZenView
  local view = {
    win = win,
    buf = buf,
    file = file,
    box = box,
    px = px,
    rect = px and require("images.viewport").full(px) or nil,
    queued = nil,
    cropping = false,
    broken = false,
    title = title,
    depth = parent and (parent.depth or 1) + 1 or 1,
    parent = parent,
    origin = opts.origin or { file = file, x = 0, y = 0 },
  }
  views[win] = view
  current = win
  map_keys(buf, zen_cfg.keys)
  map_fixed_keys(view)

  -- One group per window: with a stack open, clearing a shared group would
  -- take the other windows' resize and close handlers with it.
  local autocmd = require("lib.nvim.bindings.autocmd")
  local group = autocmd.group("images.zen." .. win, true)
  autocmd.create({ "WinResized", "VimResized" }, function()
    -- A drag or a selection measures against the picture box it started with;
    -- after a resize that box is gone, so they end rather than mapping wrongly.
    view.drag = nil
    end_select(view)
    show(view)
  end, {
    group = group,
    desc = "images.zen: image follows the window size",
  })
  autocmd.create("WinClosed", function()
    views[win] = nil
    if current == win then current = nil end
    -- `q` in the picture with the key list still open (focus moved back with
    -- <C-w>p): the list would otherwise stay up over nothing.
    close_help(view)
    require("images.terminal").clear()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if parent and not closing_all then restore(parent) end
  end, {
    group = group,
    pattern = tostring(win),
    once = true,
    desc = "images.zen: clean up on close",
  })

  show(view)
  return true
end

--- Show the image under the cursor (or at `path`) full-screen.
---
--- `opts.width`/`opts.height` (fractions of the editor) open the window at a
--- size of its own instead of `display.zen.width`/`height`; `M.resize` steps
--- on from there through `display.zen.sizes`.
---@param path string|nil nil = the image under the cursor
---@param opts { width?: number, height?: number }|nil
---@return boolean ok
function M.open(path, opts)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image found")
    return false
  end

  -- The same rule as `images.show`: where the terminal probably cannot draw
  -- and the block-graphics fallback is there, show that instead of an empty
  -- window. Otherwise draw anyway (`images.guard`: detection is a heuristic).
  local display = cfg().display
  if not require("images.terminal").capability(display.assume_supported).ok then
    local ascii_cfg = display.ascii_fallback or {}
    if ascii_cfg.enabled ~= false and require("images.ascii").available() then return require("images").show(file) end
  end

  require("images.guard").check()

  -- Replace an already open zen window (stack and all) rather than stacking.
  opts = opts or {}
  return open_view(file, { width = opts.width, height = opts.height })
end

-- ── Selection ──────────────────────────────────────────────────────────────
--
-- A rectangle is chosen without painting anything over the picture: WezTerm
-- drops the whole image as soon as Neovim writes a cell inside it (measured,
-- 2026-10-20), so there is no visual mode and no highlight. The feedback is the
-- frame's colour (`winhighlight` leaves the picture alone, measured too) and a
-- line in the command line. Releasing the button (or <CR>) cuts the rectangle
-- from the ORIGINAL file at full resolution and opens it as a zen window of its
-- own, stacked on this one.

---@class ImagesNvim.ZenOrigin
---@field file string the original image
---@field x integer where this window's file starts in it, source pixels
---@field y integer

---@class ImagesNvim.ZenSelect
---@field r1 integer first corner, content cell (1-based)
---@field c1 integer
---@field r2 integer second corner
---@field c2 integer
---@field box Images.Viewport.Box the picture box when it started
---@field rect Images.Viewport.Rect the visible rectangle when it started
---@field keys boolean chosen by keyboard (hjkl move the second corner)

--- Smaller than this on either axis, a selection is a click.
local MIN_SELECT_CELLS = 2

local HL_SELECT = "ImagesZenSelect"

---@param view ImagesNvim.ZenView
---@param on boolean
local function frame_colour(view, on)
  if not vim.api.nvim_win_is_valid(view.win) then return end
  if on then
    pcall(vim.api.nvim_set_hl, 0, HL_SELECT, { link = "DiagnosticWarn", default = true })
    view.winhl = vim.wo[view.win].winhighlight
    local entry = "FloatBorder:" .. HL_SELECT
    vim.wo[view.win].winhighlight = view.winhl ~= "" and (view.winhl .. "," .. entry) or entry
  elseif view.winhl ~= nil then
    vim.wo[view.win].winhighlight = view.winhl
    view.winhl = nil
  end
end

--- The selection as a rectangle of `view.file`, or nil while it is a click.
---@param view ImagesNvim.ZenView
---@return Images.Viewport.Rect|nil
local function selected_rect(view)
  local s = view.select
  if not s then return nil end
  return require("images.viewport").cells_to_rect(s.rect, s.box, s.r1, s.c1, s.r2, s.c2, MIN_SELECT_CELLS)
end

---@param view ImagesNvim.ZenView
local function echo_select(view)
  local rect = selected_rect(view)
  local text = rect and ("selection %d×%d px at %d,%d"):format(rect.w, rect.h, view.origin.x + rect.x, view.origin.y + rect.y)
    or "selection: drag further (a click selects nothing)"
  pcall(vim.api.nvim_echo, { { text } }, false, {})
end

---@param view ImagesNvim.ZenView
end_select = function(view)
  if not view.select then return end
  view.select = nil
  frame_colour(view, false)
  pcall(vim.api.nvim_echo, { { "" } }, false, {})
end

---@param view ImagesNvim.ZenView
---@param r integer content cell
---@param c integer
---@param by_keys boolean
local function begin_select(view, r, c, by_keys)
  if not (view.px and view.rect) then
    tell_once("select: this image does not say how large it is")
    return false
  end
  view.drag = nil
  local box = picture_box(view)
  view.select = { r1 = r, c1 = c, r2 = r, c2 = c, box = box, rect = view.rect, keys = by_keys }
  frame_colour(view, true)
  echo_select(view)
  return true
end

--- Cut `rect` (of `view.file`) from the original and open it on top of `view`.
---@param view ImagesNvim.ZenView
---@param rect Images.Viewport.Rect
---@return boolean started
function M.open_selection(view, rect)
  view = view or active()
  if not alive(view) then return false end
  if not require("lib.nvim.cross.executable").exists("magick") then
    tell_once("cutting a selection needs ImageMagick (magick) on PATH")
    return false
  end
  local vp = require("images.viewport")
  local origin = view.origin
  local in_original = { x = origin.x + rect.x, y = origin.y + rect.y, w = rect.w, h = rect.h }
  local key = crop_key(origin.file, in_original)
  local out = ("%s/sel-%s.png"):format(crop_dir(), vim.fn.sha256(key or (origin.file .. vp.geometry(in_original))))
  pcall(vim.api.nvim_echo, { { "cutting the selection …" } }, false, {})
  require("images.convert").crop(origin.file, vp.geometry(in_original), out, nil, function(path, err)
    if path and key then
      crops["sel\0" .. key] = path
      arm_cleanup()
    end
    if not alive(view) then return end
    if not path then
      notify().error(err or "could not cut the selection")
      return
    end
    pcall(vim.api.nvim_echo, { { "" } }, false, {})
    open_view(path, { parent = view, origin = { file = origin.file, x = in_original.x, y = in_original.y } })
  end)
  return true
end

--- Finish the selection: open it, or nothing for a click.
---@param view ImagesNvim.ZenView
---@return boolean opened
local function confirm_select(view)
  local rect = selected_rect(view)
  end_select(view)
  if not rect then return false end
  return M.open_selection(view, rect)
end

--- Start a mouse selection at a screen cell.
---@param screenrow integer
---@param screencol integer
---@return boolean started
function M.select_begin(screenrow, screencol)
  local view = active()
  if not view then return false end
  local row0, col0 = require("images.anchor").content_origin(view.win)
  return begin_select(view, screenrow - row0 + 1, screencol - col0 + 1, false)
end

--- Move the selection's second corner to a screen cell.
---@param screenrow integer
---@param screencol integer
---@return boolean moved
function M.select_to(screenrow, screencol)
  local view = active()
  if not (view and view.select) then return false end
  local row0, col0 = require("images.anchor").content_origin(view.win)
  view.select.r2, view.select.c2 = screenrow - row0 + 1, screencol - col0 + 1
  echo_select(view)
  return true
end

--- End the mouse selection at a screen cell and open it.
---@param screenrow integer
---@param screencol integer
---@return boolean opened
function M.select_end(screenrow, screencol)
  local view = active()
  if not (view and view.select) then return false end
  M.select_to(screenrow, screencol)
  return confirm_select(view)
end

--- Keyboard selection: start with both corners in the middle of the picture.
---@return boolean started
function M.select_keys()
  local view = active()
  if not view or view.select then return false end
  if not (view.px and view.rect) then return begin_select(view, 1, 1, true) end
  local box = picture_box(view)
  local r = box.row_off + math.max(1, math.floor(box.rows / 2))
  local c = box.col_off + math.max(1, math.floor(box.cols / 2))
  return begin_select(view, r, c, true)
end

--- Move a keyboard selection's second corner by `dr`,`dc` cells, kept on the
--- picture. What `hjkl` do while a keyboard selection is open.
---@param dr integer
---@param dc integer
---@return boolean moved
function M.select_step(dr, dc)
  local view = active()
  local s = view and view.select
  if not (s and s.keys) then return false end
  local box = s.box
  s.r2 = math.max(box.row_off + 1, math.min(box.row_off + box.rows, s.r2 + dr))
  s.c2 = math.max(box.col_off + 1, math.min(box.col_off + box.cols, s.c2 + dc))
  echo_select(view)
  return true
end

--- Confirm the active window's selection (<CR>, or the mouse release).
---@return boolean opened
function M.select_confirm()
  local view = active()
  if not (view and view.select) then return false end
  return confirm_select(view)
end

--- Drop the active window's selection without opening it.
---@return boolean dropped
function M.select_cancel()
  local view = active()
  if not (view and view.select) then return false end
  end_select(view)
  return true
end

---@param lhs string
local function pass_through(lhs)
  -- `n`: not remapped, so the default action runs, at the position the
  -- event came with -- a click beside the zen window still focuses there.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, true, true), "n", false)
end

--- The keys every zen window has whatever `display.zen.keys` says: closing,
--- and confirming or dropping a selection. `q` closes the whole stack,
--- `<Esc>` drops a selection first; `<CR>` only means something while one is
--- open.
---@param view ImagesNvim.ZenView
map_fixed_keys = function(view)
  local keymap = require("lib.nvim.bindings.keymap")
  local o = { buffer = view.buf, nowait = true }
  keymap("n", "q", function()
    M.close()
  end, o, "images: zen: close the zen window(s)")
  keymap("n", "<Esc>", function()
    if not M.select_cancel() then M.close() end
  end, o, "images: zen: drop the selection, or close")
  keymap("n", "<CR>", function()
    M.select_confirm()
  end, o, "images: zen: open the selection")

  -- The mouse selection: press, drag and release, derived like the middle
  -- drag's (multi-click variants included). Bound here rather than through
  -- the action's rhs, because a press beside the picture is handed back to
  -- Neovim as the very key that came -- a click elsewhere must still focus
  -- there and start its own visual selection.
  local function mouse_selecting()
    local here = active()
    return here and here.select and not here.select.keys and here or nil
  end
  for _, e in ipairs(require("lib.nvim.bindings.keymap").registered("images/zen")) do
    if e.name == "select_drag" and e.bound and e.lhs and e.buffer == view.buf then
      for _, v in ipairs(drag_variants(e.lhs)) do
        keymap("n", v.press, function()
          local here = active()
          local pos, over = mouse(here)
          if here then end_select(here) end
          if pos and over then
            M.select_begin(pos.screenrow, pos.screencol)
          else
            M._pass_through(v.press)
          end
        end, o, "images: zen: start a selection")
        keymap("n", v.drag, function()
          local pos = mouse(active())
          if mouse_selecting() and pos then
            M.select_to(pos.screenrow, pos.screencol)
          else
            M._pass_through(v.drag)
          end
        end, o, "images: zen: drag the selection")
        keymap("n", v.release, function()
          local pos = mouse(active())
          if mouse_selecting() and pos then
            M.select_end(pos.screenrow, pos.screencol)
          else
            M._pass_through(v.release)
          end
        end, o, "images: zen: finish the selection")
      end
    end
  end
end

--- Hand a mouse key back to Neovim unmapped. A field so a spec can watch it.
M._pass_through = pass_through

--- The selection state of the active window, for tests: corners, and the
--- rectangle it would cut.
---@return ImagesNvim.ZenSelect|nil select
---@return Images.Viewport.Rect|nil rect
function M.selection()
  local view = active()
  if not view then return nil end
  return view.select, selected_rect(view)
end

--- The active view's position in the original: file and offset. For `gs`.
---@return ImagesNvim.ZenOrigin|nil
function M.origin()
  local view = active()
  return view and view.origin
end

return M
