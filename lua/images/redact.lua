---@module 'images.redact'
---@brief Redaction mode: black out parts of an image in a zen window, leaving
--- the original intact.
---@description
--- Motivation: casedesk attachments
--- (screenshots containing customer data under `Ressources/`) that have to be
--- made unrecognisable before any future handover to an AI.
---
--- The window is a zen window (`images.zen`), and a box is chosen the way a
--- part is chosen there: drag with the left button, or `v` and then
--- hjkl/HJKL, `<CR>` takes it. Nothing is painted over the picture while
--- choosing -- WezTerm drops the whole image as soon as Neovim writes a cell
--- inside it (measured 2026-10-20), which is what made the old visual-mode
--- selection blind: pressing `v` made the picture vanish and only the empty
--- cells were left to mark. Zoom and pan work as in any zen window, so a small
--- line of text can be boxed precisely.
---
--- A confirmed box comes back in the original's pixels (`images.zen`'s
--- `on_select`) and is burned into a PREVIEW in a temporary directory, which
--- the window then shows instead of the original: every box marked so far is
--- visible as black, and the title counts them. `u` takes the last one off
--- again (a count takes that many). `w` burns them into the original's copy
--- (`photo.png` -> `photo.redacted.png`, `images.convert.redact`, ImageMagick --
--- one of the deliberate exceptions to the "ImageMagick improves, never
--- enables" guardrail, docs/architecture.md lists them all) and closes.
---
--- `display.redact.padding_cells` widens every box by that many cells of the
--- view it was chosen in, on each side: a cell is coarse, and over-redacting
--- is the safe failure mode.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@class Images.Redact.PixelBox
---@field x1 integer
---@field y1 integer
---@field x2 integer inclusive
---@field y2 integer inclusive

---@class Images.Redact.State
---@field win integer the zen window
---@field file string the original
---@field px Images.Scale.Dims its size
---@field boxes Images.Redact.PixelBox[]
---@field dir string where the previews go
---@field seq integer the preview asked for last; an older one arriving late is dropped
---@field writing boolean `w` is burning the boxes in

---@type Images.Redact.State|nil
local state = nil

--- A selection (`rect`, original pixels) widened by `padding` cells of `cell`
--- pixels on each side and clamped to the picture `px`, as the inclusive
--- corners `images.convert.redact` draws. Pure.
---@param rect Images.Viewport.Rect
---@param cell { w: number, h: number }
---@param padding integer
---@param px Images.Scale.Dims
---@return Images.Redact.PixelBox
function M.pixel_box(rect, cell, padding, px)
  -- `padding` is `display.redact.padding_cells` verbatim: a non-number would
  -- throw in the arithmetic below, and a negative one would shrink the box --
  -- the opposite of what the margin is for. Both count as no margin (ERR-22).
  if type(padding) ~= "number" or padding ~= padding or padding < 0 then padding = 0 end
  local pad_x = math.ceil(padding * cell.w)
  local pad_y = math.ceil(padding * cell.h)
  return {
    x1 = math.max(0, rect.x - pad_x),
    y1 = math.max(0, rect.y - pad_y),
    x2 = math.min(px.width - 1, rect.x + rect.w - 1 + pad_x),
    y2 = math.min(px.height - 1, rect.y + rect.h - 1 + pad_y),
  }
end

--- Whether a redaction window is currently open.
---@return boolean
function M.is_open()
  return state ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- The boxes marked so far, in the original's pixels (a copy).
---@return Images.Redact.PixelBox[]
function M.boxes()
  return state and vim.deepcopy(state.boxes) or {}
end

---@param s Images.Redact.State
local function forget(s)
  if state == s then state = nil end
  vim.fn.delete(s.dir, "rf")
end

--- Close the redaction window (a no-op when none is open). Discards the boxes
--- -- original and target file are untouched at that point anyway, only `w`
--- writes.
---@return nil
function M.close()
  local s = state
  if not s then return end
  if vim.api.nvim_win_is_valid(s.win) then pcall(vim.api.nvim_win_close, s.win, true) end
  forget(s)
end

--- Show the original with every box so far burned in -- or the original itself
--- once none is left. The latest request wins: a slow `magick` for two boxes
--- finishing after the one for three would otherwise show the wrong set.
---@param s Images.Redact.State
local function refresh(s)
  s.seq = s.seq + 1
  local seq = s.seq
  if #s.boxes == 0 then
    require("images.zen").show_file(s.win, s.file)
    return
  end
  local ext = vim.fn.fnamemodify(s.file, ":e")
  local out = ("%s/preview-%d.%s"):format(s.dir, seq, ext ~= "" and ext or "png")
  require("images.convert").redact(s.file, s.boxes, function(path, err)
    if state ~= s or seq ~= s.seq then return end
    if not path then
      -- The window still shows the previous set: say that it is not what `w`
      -- writes now.
      notify().error(
        ("%s -- the picture shows an older set of boxes, `w` burns in the %d marked now"):format(
          err or "could not draw the preview",
          #s.boxes
        )
      )
      return
    end
    require("images.zen").show_file(s.win, path)
  end, out)
end

--- While `w` burns the boxes in, the set is fixed: a box marked now would not
--- be in the file, and the window closes when it is written.
---@param s Images.Redact.State
---@return boolean busy
local function writing(s)
  if s.writing then notify().warn("writing the redacted copy … the boxes are fixed until it is done") end
  return s.writing
end

---@param s Images.Redact.State
---@param rect Images.Viewport.Rect in the pixels of the picture the zen window measured
---@param cell { w: number, h: number }
---@param px Images.Scale.Dims|nil that picture's size (the zen view's), `s.px` without one
local function add_box(s, rect, cell, px)
  if writing(s) then return end
  local padding = (cfg().display.redact or {}).padding_cells or 0
  s.boxes[#s.boxes + 1] = M.pixel_box(rect, cell, padding, px or s.px)
  refresh(s)
end

---A count removes that many boxes: `3u` after marking a run of them in the
---wrong place beats pressing `u` three times. Clamped to what is there.
---@param s Images.Redact.State
local function undo_box(s)
  if writing(s) then return end
  if #s.boxes == 0 then
    notify().warn("no box to remove")
    return
  end
  for _ = 1, math.min(vim.v.count1, #s.boxes) do
    table.remove(s.boxes)
  end
  refresh(s)
end

---@param s Images.Redact.State
local function write_redacted(s)
  if #s.boxes == 0 then
    notify().warn("no box marked — nothing to redact")
    return
  end
  if s.writing then return end
  -- A keyboard selection still open (`v` + hjkl, no <CR> yet) is a box the
  -- user means and has not taken: writing now would leave it out.
  if require("images.zen").selection() then
    notify().warn("a selection is still open -- <CR> takes it, <Esc> drops it, then `w`")
    return
  end
  s.writing = true
  -- Asynchronous: the window stays up until the result arrives and is closed
  -- only then, so a failure leaves the boxes to try again with.
  require("images.convert").redact(s.file, s.boxes, function(out, err)
    s.writing = false
    if not out then
      notify().error(err or "redaction failed")
      return
    end
    -- Closing the window while it ran does not undo it: the file is written,
    -- and saying so beats a copy nobody expects.
    notify().info("redacted copy saved: " .. vim.fn.fnamemodify(out, ":~"))
    if state == s then M.close() end
  end)
end

--- Open an image — or the one under the cursor — in redaction mode.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.open(path)
  local target = require("images.resolve").path_or_cursor(path)
  if not target then
    notify().warn("no image under the cursor or at the given path")
    return false
  end
  if not require("lib.nvim.cross.executable").exists("magick") then
    notify().error("`:Image redact` needs ImageMagick (`magick` not found)")
    return false
  end
  -- A vector image has no pixels to box: its header says no size the zen
  -- window could map a selection onto, and burning a rectangle into an SVG
  -- through magick rasterizes it anyway.
  if target:lower():match("%.svgz?$") then
    notify().error("`:Image redact` works on raster images -- convert the SVG first (`:Image convert png`)")
    return false
  end

  local px, info_err = require("images.info").collect(target)
  if not px or not px.width or not px.height then
    notify().error(info_err or "cannot determine the image dimensions")
    return false
  end

  M.close()

  ---@type Images.Redact.State
  local s = {
    win = -1,
    file = target,
    px = { width = px.width, height = px.height },
    boxes = {},
    dir = vim.fn.tempname() .. "-images-redact",
    seq = 0,
    writing = false,
  }
  vim.fn.mkdir(s.dir, "p")
  -- Set before the window opens: its first draw already asks for the label.
  state = s

  local zen = require("images.zen")
  local ok = zen.open(target, {
    on_select = function(view, rect, cell)
      if state == s then add_box(s, rect, cell, view.px) end
    end,
    label = function()
      if state ~= s then return nil end
      return ("redact · %d box%s"):format(#s.boxes, #s.boxes == 1 and "" or "es")
    end,
    -- The block-graphics fallback has no selection: on a terminal that does not
    -- look image-capable, draw anyway, as `:Image redact` always did.
    fallback = false,
  })
  local win = ok and zen.win() or nil
  if not win then
    forget(s)
    notify().error("could not open the redaction window")
    return false
  end
  s.win = win

  local buf = vim.api.nvim_win_get_buf(win)
  local map = require("lib.nvim.bindings.keymap")
  map("n", "w", function()
    write_redacted(s)
  end, { buffer = buf, nowait = true }, "images.redact: burn the boxes in and save")
  map("n", "u", function()
    undo_box(s)
  end, { buffer = buf, nowait = true }, "images.redact: remove the last box")

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    forget(s)
  end, {
    group = autocmd.group("images.redact", true),
    pattern = tostring(win),
    once = true,
    desc = "images.redact: drop the boxes and previews on close",
  })

  notify().info("redact: drag (or v, hjkl, <CR>) to mark a box · u removes the last · w saves")
  return true
end

return M
