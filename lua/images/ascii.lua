---@module 'images.ascii'
---@brief Draw an image as coloured block graphics when OSC 1337 is
--- unavailable.
---@description
--- The fallback for any terminal without a graphics protocol (SSH, tmux
--- without passthrough, an unrecognised terminal).
---
--- Originally considered as a color_my_ascii.nvim integration. Its highlighter
--- colours known ASCII character classes (arrows, box drawing, operators, …)
--- against a named scheme — pattern-based, one colour per class. An image, by
--- contrast, needs an arbitrary RGB colour per cell derived from real pixels;
--- that is a different kind of colouring, and not one color_my_ascii offers.
--- Hence a small dedicated path straight over `nvim_set_hl`/extmarks instead of
--- a dependency that does not fit.
---
--- Requires ImageMagick — one of the deliberate exceptions to the
--- "ImageMagick improves, never enables" guardrail (docs/architecture.md lists
--- them all): reading pixel colours out of an arbitrary raster file needs a
--- real image decoder, which plain Lua does not have.
---
--- Every terminal cell becomes a "█" character with its own foreground colour —
--- truecolour block graphics as used by graphics-protocol-less image viewers
--- (chafa, viu), rather than a brightness character ramp (" .:-=+*#%@"). More
--- faithful to the colours, and without the extra question of "which character
--- for which brightness".
---
--- The sampling and painting themselves live in `images.blocks`, which is also
--- what a frame sequence draws through. Moving them there fixed a fault this
--- module had latently: it created one highlight group per *exact* colour, in
--- a session-wide cache, and Neovim stops at 19 602 groups (measured
--- 2026-09-08). Enough images and `E849` ends the session's colouring for
--- good. `blocks` quantises to `levels` steps per channel, which caps the
--- count at `levels³` — 4 096 by default.
---
--- Deliberately the single-image path only (`images.init.M.show`) — the same
--- scope boundary as remote images (see images.remote): gallery, compare,
--- pickers and zen do not get this (yet).

local M = {}

local blocks = require("images.blocks")

local NS = vim.api.nvim_create_namespace("images.ascii")

--- The currently open ASCII window, if there is one.
---@type integer|nil
local winid = nil

---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Close the window (a no-op when none is open).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  winid = nil
end

--- Whether ImageMagick is available — this module's only prerequisite.
---@return boolean
function M.available()
  return blocks.available()
end

--- Draw the image as coloured block graphics in a floating window under the
--- cursor.
---@param path string absolute path
---@param display ImagesNvim.DisplayConfig
---@return boolean ok
---@return string|nil err
function M.open(path, display)
  if not M.available() then return false, "the ASCII fallback requires ImageMagick (`magick` not found)" end

  local info = require("images.info").collect(path)
  local image_px = (info and info.width and info.height) and { width = info.width, height = info.height } or nil
  -- `blocks.fit_cells`, not `images.scale.fit_cells`: a half block holds two
  -- pixels, which makes them square, and the other function corrects for a
  -- cell being twice as tall as it is wide. Using it here halves the picture.
  local cols, rows = blocks.fit_cells(display.max_cols, display.max_rows, image_px)

  local raw, err = blocks.sample({ path }, cols, rows)
  if not raw then return false, err end

  M.close()

  local win, buf = require("lib.nvim.window.make_scratch")({
    relative = "cursor",
    row = 1,
    col = 0,
    width = cols,
    height = rows,
    lines = blocks.canvas_lines(cols, rows),
    enter = false,
    focusable = false,
    border = "rounded",
    title = " ASCII (no OSC 1337) ",
  })
  if not win or not buf then return false, "could not open the ASCII window" end
  winid = win

  local ok_paint, paint_err = blocks.paint(buf, NS, raw, 1, cols, rows, (display.ascii_fallback or {}).levels)
  if not ok_paint then
    M.close()
    return false, paint_err
  end

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    winid = nil
  end, {
    group = autocmd.group("images.ascii", true),
    pattern = tostring(winid),
    once = true,
    desc = "images.ascii: clean up on close",
  })

  return true
end

return M
