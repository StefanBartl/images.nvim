-- TESTS/viewport_spec.lua — images.viewport: the zoom / pan / selection arithmetic
-- behind the zen window's magnified view.
--
-- Pure computation, no terminal needed — the same separation as `images.scale`.

---@param H table harness from TESTS/run.lua
return function(H)
  local vp = require("images.viewport")
  local scale = require("images.scale")

  -- `images.cell` may have set a calibrated aspect; the numbers below assume the default.
  local saved_aspect = scale.CELL_ASPECT
  scale.CELL_ASPECT = 0.5

  local function same(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
  end
  local function show(r)
    return r and vp.geometry(r) or "nil"
  end

  local hd = { width = 1920, height = 1080 }

  -- ── The whole picture ────────────────────────────────────────────────────
  local full = vp.full(hd)
  H.eq(show(full), "1920x1080+0+0", "full: the whole picture")
  H.ok(vp.is_full(hd, full), "is_full: the whole picture is full")
  H.eq(vp.factor(hd, full), 1, "factor: 1 when not zoomed")

  -- ── rect_for: hover.nvim's level/centre zoom ─────────────────────────────
  H.ok(same(vp.rect_for(hd, 0, 0.5, 0.5), full), "rect_for: level 0 is the whole picture")
  H.eq(show(vp.rect_for(hd, 1, 0.5, 0.5)), "1280x720+320+180", "rect_for: one step in, centred")
  H.eq(show(vp.rect_for(hd, 1, 0, 0)), "1280x720+0+0", "rect_for: a centre at the edge is pushed back inside")
  H.eq(show(vp.rect_for({ width = 100, height = 100 }, 10, 0.5, 0.5)), "32x32+34+34", "rect_for: stops at FLOOR_PX")

  -- ── zoom_at: the point under the pointer stays put ───────────────────────
  local half = vp.zoom_at(hd, full, 2)
  H.eq(show(half), "960x540+480+270", "zoom_at: factor 2 around the centre")
  H.ok(not vp.is_full(hd, half), "is_full: a zoomed rectangle is not full")
  H.eq(vp.factor(hd, half), 2, "factor: 2 after zooming by 2")

  local at = vp.zoom_at(hd, full, 2, 0.25, 0.75)
  H.eq(show(at), "960x540+240+405", "zoom_at: around a point off-centre")
  -- The picture point (480, 810) was at 25% / 75% of the view and still is.
  H.eq((480 - at.x) / at.w, 0.25, "zoom_at: the fixed point keeps its horizontal place")
  H.eq((810 - at.y) / at.h, 0.75, "zoom_at: the fixed point keeps its vertical place")

  H.ok(same(vp.zoom_at(hd, at, 0.5, 0.25, 0.75), full), "zoom_at: zooming back out returns to the whole picture")
  H.ok(same(vp.zoom_at(hd, half, 0.01), full), "zoom_at: zooming out stops at the whole picture")
  H.ok(vp.zoom_at(hd, full, 0.5) == full, "zoom_at: nothing to zoom out of returns the same table")
  H.eq(show(vp.zoom_at(hd, half, 1.5)), "640x360+640+360", "zoom_at: keeps the aspect ratio")
  -- A view narrower in height than the picture's ratio: its width reaches the edge
  -- first, and that ends the zoom-out -- the height must not be stretched to 675.
  H.ok(
    same(vp.zoom_at(hd, { x = 0, y = 0, w = 960, h = 270 }, 0.4), full),
    "zoom_at: the first axis to reach the edge ends the zoom-out"
  )

  local small = { width = 100, height = 100 }
  local deep = vp.zoom_at(small, vp.full(small), 10)
  H.eq(deep.w, vp.FLOOR_PX, "zoom_at: zooming in stops at FLOOR_PX")
  H.ok(not vp.can_zoom(small, deep, vp.ZOOM_STEP), "can_zoom: no further in at the floor")
  H.ok(vp.can_zoom(small, deep, 1 / vp.ZOOM_STEP), "can_zoom: but out again")
  H.ok(not vp.can_zoom(hd, full, 1 / vp.ZOOM_STEP), "can_zoom: no further out than the whole picture")
  H.ok(vp.zoom_at(hd, half, 0 / 0) == half, "zoom_at: a NaN factor changes nothing")
  H.ok(vp.zoom_at(hd, half, -2) == half, "zoom_at: a negative factor changes nothing")

  -- A strip at the floor that spans the picture on one axis: further in is impossible,
  -- and that must not turn into "out to the whole picture" (both limits are 1 there).
  local square = { width = 1000, height = 1000 }
  local strip = { x = 0, y = 500, w = 1000, h = 32 }
  H.ok(vp.zoom_at(square, strip, 1.5) == strip, "zoom_at: a strip at the floor stays put on a zoom in")
  H.ok(not vp.can_zoom(square, strip, 1.5), "can_zoom: and says so")
  local wide = { width = 1000, height = 20 }
  local first = vp.rect_for(wide, 1, 0.5, 0.5)
  H.eq(show(first), "666x20+167+0", "rect_for: a picture lower than the floor keeps its height")
  H.ok(vp.zoom_at(wide, first, 1.5) == first, "zoom_at: zooming in on it does not jump back out")

  -- NaN never reaches the clamps (under LuaJIT math.min(1, NaN) is NaN).
  H.eq(show(vp.zoom_at(hd, full, 2, 0 / 0, 0 / 0)), "960x540+480+270", "zoom_at: a NaN point is the centre")
  H.ok(vp.pan(hd, half, 0 / 0, 0 / 0) == half, "pan: a NaN distance does not move")

  -- A picture that is itself smaller than the floor cannot be zoomed at all.
  local tiny = { width = 20, height = 10 }
  H.ok(not vp.can_zoom(tiny, vp.full(tiny), 2), "can_zoom: a picture under FLOOR_PX stays whole")

  -- ── pan / pan_by / drag ──────────────────────────────────────────────────
  H.ok(vp.pan(hd, full, 100, 100) == full, "pan: the whole picture cannot move")
  H.eq(show(vp.pan(hd, half, -1000, 0)), "960x540+0+270", "pan: clamped at the left edge")
  H.eq(show(vp.pan_by(hd, half, 0.25, 0)), "960x540+720+270", "pan_by: a quarter of the visible width")
  H.eq(show(vp.pan_by(hd, half, math.huge, 0)), "960x540+960+270", "pan_by: math.huge reaches the right edge")
  H.eq(show(vp.pan_by(hd, half, 0, -math.huge)), "960x540+480+0", "pan_by: -math.huge reaches the top edge")

  local box96 = { cols = 96, rows = 27, col_off = 0, row_off = 0 }
  -- 960 px over 96 cells: 10 px per cell. Dragging 3 cells right shows 30 px further left.
  H.eq(show(vp.drag(hd, half, box96, 3, 0)), "960x540+450+270", "drag: the picture follows the pointer")
  H.eq(show(vp.drag(hd, half, box96, 0, -2)), "960x540+480+310", "drag: dragging up shows what is below")

  -- ── image_box: the box the picture is really drawn in ────────────────────
  -- ROADMAP/TERMINALS.md failure mode 6, with a 2:1 picture: a 77x20 window, one cell of
  -- inset leaves 75x18, and the picture fills 72x18 of it, centred.
  local box = vp.image_box(77, 20, 1, { x = 0, y = 0, w = 2000, h = 1000 })
  H.eq(box.cols, 72, "image_box: fitted width")
  H.eq(box.rows, 18, "image_box: fitted height")
  H.eq(box.col_off, 2, "image_box: inset plus half the letterbox")
  H.eq(box.row_off, 1, "image_box: inset only, the height binds")

  local cols, rows, col_off, row_off = scale.draw_box(77, 20, "full", nil, 1, { width = 2000, height = 1000 })
  H.ok(
    cols == box.cols and rows == box.rows and col_off == box.col_off and row_off == box.row_off,
    "image_box: the same box images.anchor draws in (scale.draw_box)"
  )

  -- ── fraction_at ──────────────────────────────────────────────────────────
  local b = { cols = 10, rows = 10, col_off = 2, row_off = 1 }
  local fx, fy, inside = vp.fraction_at(b, 2, 3)
  H.eq(fx, 0.05, "fraction_at: the first picture cell's centre, horizontally")
  H.eq(fy, 0.05, "fraction_at: and vertically")
  H.ok(inside, "fraction_at: that cell is on the picture")
  local margin_fx, _, margin_inside = vp.fraction_at(b, 2, 1)
  H.eq(margin_fx, 0, "fraction_at: a margin cell clamps onto the picture's edge")
  H.ok(not margin_inside, "fraction_at: and says it is not on the picture")

  -- ── cells_to_rect: a selection in cells becomes a source rectangle ───────
  local pic = { x = 0, y = 0, w = 1000, h = 500 }
  local grid = { cols = 100, rows = 50, col_off = 0, row_off = 0 }
  H.eq(show(vp.cells_to_rect(pic, grid, 1, 1, 10, 20)), "200x100+0+0", "cells_to_rect: 20x10 cells are 200x100 px")
  H.eq(show(vp.cells_to_rect(pic, grid, 10, 20, 1, 1)), "200x100+0+0", "cells_to_rect: any two opposite corners")
  H.eq(show(vp.cells_to_rect(pic, grid, -5, -5, 999, 999)), "1000x500+0+0", "cells_to_rect: overshoot is clamped")
  H.eq(vp.cells_to_rect(pic, grid, 5, 5, 6, 5), nil, "cells_to_rect: one column wide is a click, not a selection")
  H.eq(
    vp.cells_to_rect(pic, { cols = 5, rows = 5, col_off = 10, row_off = 0 }, 1, 1, 5, 5),
    nil,
    "cells_to_rect: a selection beside the picture is nothing"
  )

  local zoomed = { x = 100, y = 50, w = 1000, h = 500 }
  H.eq(show(vp.cells_to_rect(zoomed, grid, 1, 1, 10, 20)), "200x100+100+50", "cells_to_rect: offset by the visible rectangle")
  local shifted = { cols = 100, rows = 50, col_off = 3, row_off = 2 }
  H.eq(
    show(vp.cells_to_rect(pic, shifted, 3, 4, 12, 23)),
    "200x100+0+0",
    "cells_to_rect: measured from the picture box, not the window"
  )

  scale.CELL_ASPECT = saved_aspect
end
