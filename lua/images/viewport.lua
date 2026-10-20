---@module 'images.viewport'
---@brief Pure computation: which rectangle of a picture is on screen, and how
--- zooming, panning and selecting move it.
---@description
--- The zen window can show a part of an image rather than the whole of it.
--- This module is the arithmetic for that, and nothing else: no window, no
--- terminal, no file, so every rule below is checked headless (like
--- `images.scale`, which it builds on).
---
--- **A rectangle is in source pixels, `{ x, y, w, h }`, 0-based.** The whole
--- picture is `{ 0, 0, width, height }`; the zen window always has a
--- rectangle, never "no zoom" as a separate state, so there is one code path.
---
--- **Cells come in through `M.image_box`.** OSC 1337 places whole cells only
--- and the picture is not flush with its window: `display.draw_inset` keeps a
--- margin, and inside it the picture is fitted to its own aspect ratio and
--- centred (`images.scale.draw_box`, the same function `images.anchor` draws
--- with). Mapping a cell to a pixel against the window instead of that box put
--- a selection 2-3 cells off in measurement (images.nvim ROADMAP/TERMINALS.md,
--- failure mode 6). Converting a SCREEN cell into a window content cell is the
--- caller's part -- it needs the live window.
---
--- The zoom constants come from hover.nvim's picture zoom, measured there: one
--- step costs a `magick` crop (~250 ms for a 1080p screenshot on Windows), so
--- 1.5 reaches 5x in four presses, and below 32 source pixels there is nothing
--- left to magnify, only blur.

local M = {}

---@type number What one zoom step divides the visible rectangle by.
M.ZOOM_STEP = 1.5

---@type integer Smallest side a rectangle may shrink to, in source pixels.
M.FLOOR_PX = 32

---@class Images.Viewport.Rect
---@field x integer left edge, source pixels, 0-based
---@field y integer top edge
---@field w integer width, >= 1
---@field h integer height, >= 1

---@class Images.Viewport.Box
---@field cols integer cells the picture covers
---@field rows integer
---@field col_off integer 0-based offset of its first column inside the window content
---@field row_off integer

--- The whole picture.
---@param px Images.Scale.Dims
---@return Images.Viewport.Rect
function M.full(px)
  return { x = 0, y = 0, w = px.width, h = px.height }
end

--- Whether `rect` is the whole picture.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@return boolean
function M.is_full(px, rect)
  return rect.x == 0 and rect.y == 0 and rect.w >= px.width and rect.h >= px.height
end

--- How far in `rect` is, as a factor of the whole picture (1 = not zoomed).
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@return number
function M.factor(px, rect)
  return math.max(px.width / rect.w, px.height / rect.h)
end

--- `value` when it is a number other than NaN, else `default`. The clamps
--- below cannot clean a NaN themselves: under LuaJIT `math.min(1, 0/0)` is NaN,
--- and a NaN position ended up at the picture's bottom-right edge.
---@param value any
---@param default number
---@return number
local function finite(value, default)
  if type(value) == "number" and value == value then return value end
  return default
end

--- Integer rectangle of size `w`x`h` (floats allowed) at `x`,`y`, pushed back
--- inside the picture: a view near an edge stays full-size rather than hanging
--- off it.
---@param px Images.Scale.Dims
---@return Images.Viewport.Rect
local function clamp(px, x, y, w, h)
  w = math.max(1, math.min(px.width, math.floor(w + 0.5)))
  h = math.max(1, math.min(px.height, math.floor(h + 0.5)))
  x = math.max(0, math.min(math.floor(x + 0.5), px.width - w))
  y = math.max(0, math.min(math.floor(y + 0.5), px.height - h))
  return { x = x, y = y, w = w, h = h }
end

--- The rectangle zoom `level` (0 = whole) shows around the centre `cx`,`cy`
--- (fractions 0..1 of the picture). A fraction rather than a pixel survives a
--- level change, so stepping keeps looking at the same place. Same result as
--- hover.nvim's `zoom_rect`, except that level 0 is the full rectangle instead
--- of nil.
---@param px Images.Scale.Dims
---@param level integer
---@param cx number
---@param cy number
---@return Images.Viewport.Rect
function M.rect_for(px, level, cx, cy)
  if level <= 0 then return M.full(px) end
  local factor = M.ZOOM_STEP ^ level
  local w = math.min(px.width, math.max(M.FLOOR_PX, math.floor(px.width / factor)))
  local h = math.min(px.height, math.max(M.FLOOR_PX, math.floor(px.height / factor)))
  return clamp(px, cx * px.width - w / 2, cy * px.height - h / 2, w, h)
end

--- Zoom `rect` by `factor` (> 1 in, < 1 out) so that the picture point at
--- `fx`,`fy` (fractions 0..1 of the visible rectangle, e.g. under the mouse)
--- stays where it is on screen. The aspect ratio of `rect` is kept; zooming in
--- stops at `M.FLOOR_PX` on the shorter side, zooming out at the whole picture.
--- Returns `rect` itself (same table) when nothing would change, so a caller
--- can skip the crop: `M.zoom_at(...) == rect`.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@param factor number
---@param fx number|nil default 0.5
---@param fy number|nil default 0.5
---@return Images.Viewport.Rect
function M.zoom_at(px, rect, factor, fx, fy)
  fx = math.max(0, math.min(1, finite(fx, 0.5)))
  fy = math.max(0, math.min(1, finite(fy, 0.5)))
  if type(factor) ~= "number" or factor <= 0 or factor ~= factor then return rect end

  -- The furthest in and out this rectangle may go, as factors on its own size.
  -- Out: the first axis to reach the picture's edge ends it (the larger ratio),
  -- or the other axis would run past the picture and the aspect ratio tip over.
  local max_in = math.max(1, math.min(rect.w, rect.h) / M.FLOOR_PX)
  local max_out = math.max(rect.w / px.width, rect.h / px.height)
  local zoom_out = factor < 1
  factor = math.max(max_out, math.min(max_in, factor))
  -- Clamped to no change at all: a rectangle already at the floor cannot go
  -- further in, and one that spans the picture on one axis gives the same
  -- limit of 1 for going out. Without this a zoom IN on such a rectangle fell
  -- through to the outer limit below and came back as the whole picture.
  if math.abs(factor - 1) < 1e-9 then return rect end

  local w, h = rect.w / factor, rect.h / factor
  -- At the outer limit, be the whole picture exactly rather than a rounding of it.
  if zoom_out and factor <= max_out + 1e-9 then
    w, h = px.width, px.height
  end
  local anchor_x = rect.x + fx * rect.w
  local anchor_y = rect.y + fy * rect.h
  local out = clamp(px, anchor_x - fx * w, anchor_y - fy * h, w, h)
  if out.x == rect.x and out.y == rect.y and out.w == rect.w and out.h == rect.h then return rect end
  return out
end

--- Whether a zoom step by `factor` from `rect` would change anything.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@param factor number
---@return boolean
function M.can_zoom(px, rect, factor)
  return M.zoom_at(px, rect, factor) ~= rect
end

--- Move `rect` by `dx`,`dy` source pixels (positive = the view moves right /
--- down, so the picture appears to move left / up), clamped to the picture.
--- Returns `rect` itself when it cannot move.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@param dx number
---@param dy number
---@return Images.Viewport.Rect
function M.pan(px, rect, dx, dy)
  local out = clamp(px, rect.x + finite(dx, 0), rect.y + finite(dy, 0), rect.w, rect.h)
  if out.x == rect.x and out.y == rect.y then return rect end
  return out
end

--- Move `rect` by a fraction of its own size (`0.25` = a quarter of the visible
--- width/height) -- what a pan key does. `math.huge` reaches the edge.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@param fx number
---@param fy number
---@return Images.Viewport.Rect
function M.pan_by(px, rect, fx, fy)
  local function step(f, size)
    if f == math.huge or f == -math.huge then return f end
    return f * size
  end
  local dx, dy = step(fx, rect.w), step(fy, rect.h)
  if dx == math.huge then dx = px.width end
  if dx == -math.huge then dx = -px.width end
  if dy == math.huge then dy = px.height end
  if dy == -math.huge then dy = -px.height end
  return M.pan(px, rect, dx, dy)
end

--- Move `rect` by a drag of `dcols`,`drows` cells across `box`, the way a hand
--- moves paper: dragging right shows what is further left. The pixel distance
--- of one cell is the visible rectangle's, so a drag moves the picture exactly
--- with the pointer at any zoom.
---@param px Images.Scale.Dims
---@param rect Images.Viewport.Rect
---@param box Images.Viewport.Box
---@param dcols integer
---@param drows integer
---@return Images.Viewport.Rect
function M.drag(px, rect, box, dcols, drows)
  return M.pan(px, rect, -dcols * rect.w / box.cols, -drows * rect.h / box.rows)
end

--- The box the picture showing `rect` really covers in a window whose content
--- is `win_width`x`win_height` cells, with `margin` cells of `draw_inset`.
---@param win_width integer
---@param win_height integer
---@param margin integer
---@param rect Images.Viewport.Rect
---@return Images.Viewport.Box
function M.image_box(win_width, win_height, margin, rect)
  local cols, rows, col_off, row_off =
    require("images.scale").draw_box(win_width, win_height, "full", nil, margin, { width = rect.w, height = rect.h })
  return { cols = cols or win_width, rows = rows or win_height, col_off = col_off or 0, row_off = row_off or 0 }
end

--- Where the content cell `row`,`col` (1-based, window content) falls on the
--- visible rectangle, as fractions 0..1 of it -- the cell's centre, clamped to
--- the picture when the cell lies in the margin. The second return value says
--- whether the cell is on the picture at all.
---@param box Images.Viewport.Box
---@param row integer
---@param col integer
---@return number fx
---@return number fy
---@return boolean inside
function M.fraction_at(box, row, col)
  local c = col - box.col_off - 0.5
  local r = row - box.row_off - 0.5
  local inside = c >= 0 and c < box.cols and r >= 0 and r < box.rows
  return math.max(0, math.min(1, c / box.cols)), math.max(0, math.min(1, r / box.rows)), inside
end

--- The source rectangle covered by the cells from `row1`,`col1` to
--- `row2`,`col2` (1-based window content cells, inclusive, any two opposite
--- corners). Cells outside the picture are clamped onto it, so a drag that
--- overshoots the edge selects up to the edge. nil when the selection is
--- smaller than `min_cells` on either axis (a click, not a drag), or misses
--- the picture entirely.
---@param rect Images.Viewport.Rect
---@param box Images.Viewport.Box
---@param row1 integer
---@param col1 integer
---@param row2 integer
---@param col2 integer
---@param min_cells integer|nil default 2
---@return Images.Viewport.Rect|nil
function M.cells_to_rect(rect, box, row1, col1, row2, col2, min_cells)
  min_cells = min_cells or 2
  local function span(a, b, off, n)
    local lo = math.max(1, math.min(a, b) - off)
    local hi = math.min(n, math.max(a, b) - off)
    return lo, hi
  end
  local c1, c2 = span(col1, col2, box.col_off, box.cols)
  local r1, r2 = span(row1, row2, box.row_off, box.rows)
  if c2 - c1 + 1 < min_cells or r2 - r1 + 1 < min_cells then return nil end

  local sx, sy = rect.w / box.cols, rect.h / box.rows
  local x1 = rect.x + math.floor((c1 - 1) * sx)
  local y1 = rect.y + math.floor((r1 - 1) * sy)
  local x2 = rect.x + math.min(rect.w, math.ceil(c2 * sx))
  local y2 = rect.y + math.min(rect.h, math.ceil(r2 * sy))
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- `rect` as an ImageMagick crop geometry, `WxH+X+Y`.
---@param rect Images.Viewport.Rect
---@return string
function M.geometry(rect)
  return ("%dx%d+%d+%d"):format(rect.w, rect.h, rect.x, rect.y)
end

return M
