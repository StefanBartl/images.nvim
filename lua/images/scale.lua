---@module 'images.scale'
---@brief Pure computation: how large two images should appear relative to
--- each other.
---@description
--- Without this, `:Image compare` would stretch each image onto its pane
--- independently — a 200x100 icon next to a 4000x2000 photo would then look
--- the same size, exactly the problem FEATURES.md describes for the gallery
--- ("normalised away"). With real pixel dimensions (via `images.info`, when
--- ImageMagick is installed) the smaller image gets a proportionally smaller
--- box instead of filling its pane.
---
--- A pure module: no terminal or filesystem access, and therefore testable
--- without a terminal, like `images.gallery`.

local M = {}

--- How far an image may shrink relative to the larger one before it would
--- become unreadable. 0.35 means: even a tiny icon next to a huge photo still
--- shows at least 35% of the pane — enough to convey "smaller" without
--- disappearing.
M.MIN_SCALE = 0.35

--- Pixel dimensions before anyone has looked: `images.info.collect` fills
--- `width`/`height` only when ImageMagick is installed, so this -- not
--- `Images.Scale.Dims` -- is the shape every caller in this plugin actually
--- holds. The two functions that document a fallback for missing dimensions
--- take this one.
---@class Images.Scale.MaybeDims
---@field width integer|nil pixels, when they could be read
---@field height integer|nil pixels, when they could be read

--- The same pair, both known -- what a caller that divides by them needs. Narrowed once at the place that checked, rather than
--- re-checked at every use.
---@class Images.Scale.Dims : Images.Scale.MaybeDims
---@field width integer pixels
---@field height integer pixels

---@class Images.Scale.Result
---@field a number factor for image A, 0 < a <= 1
---@field b number factor for image B, 0 < b <= 1

--- Compute scale factors for two images. The comparison runs over the image
--- diagonal (`sqrt(w²+h²)`) as a single size value — for differing aspect
--- ratios there is no uniquely "correct" metric, but the diagonal is a common
--- and comprehensible choice.
---
--- Without both dimensions (e.g. because ImageMagick is missing) both get 1.0
--- — exactly the previous behaviour, each image fills its pane. Per the
--- guardrail, ImageMagick improves features but
--- never enables them.
---@param a Images.Scale.MaybeDims|nil
---@param b Images.Scale.MaybeDims|nil
---@return Images.Scale.Result
function M.compute(a, b)
  -- `a.width and a.width > 0`, not `a.width > 0`: without ImageMagick the
  -- fields are nil, and comparing nil to a number is an error rather than a
  -- fallback. `:Image compare` went through here with exactly that pair.
  if
    not (
      a
      and b
      and a.width
      and a.height
      and b.width
      and b.height
      and a.width > 0
      and a.height > 0
      and b.width > 0
      and b.height > 0
    )
  then
    return { a = 1, b = 1 }
  end

  local diag_a = math.sqrt(a.width ^ 2 + a.height ^ 2)
  local diag_b = math.sqrt(b.width ^ 2 + b.height ^ 2)

  if diag_a == diag_b then return { a = 1, b = 1 } end

  local ratio = math.max(M.MIN_SCALE, math.min(diag_a, diag_b) / math.max(diag_a, diag_b))
  if diag_a > diag_b then return { a = 1, b = ratio } end
  return { a = ratio, b = 1 }
end

--- Default scaling for a named position without an explicit `scale` (see
--- `M.anchor_box`) — small enough that edge positions such as "top-left" are
--- recognisably different from a full-area display.
M.DEFAULT_ANCHOR_SCALE = 0.45

--- Horizontal/vertical fraction (0 = edge, 0.5 = centred, 1 = opposite edge)
--- of the leftover space a box takes up — the same formula for all nine
--- positions, only with different (h, v). "full" needs no special case: at
--- `scale = 1`, `win_width - cols == 0`, so every anchor yields offset 0
--- anyway.
---@type table<string, { h: number, v: number }>
local ANCHORS = {
  full = { h = 0.5, v = 0.5 },
  ["top-left"] = { h = 0, v = 0 },
  top = { h = 0.5, v = 0 },
  ["top-right"] = { h = 1, v = 0 },
  ["center-left"] = { h = 0, v = 0.5 },
  center = { h = 0.5, v = 0.5 },
  ["center-right"] = { h = 1, v = 0.5 },
  ["bottom-left"] = { h = 0, v = 1 },
  bottom = { h = 0.5, v = 1 },
  ["bottom-right"] = { h = 1, v = 1 },
}

--- Valid position names, in order — for validation, `<Tab>` completion and
--- documentation, so that neither list can drift out of step with the other.
---@type string[]
M.POSITIONS = { "full" }
for _, name in ipairs({
  "top-left",
  "top",
  "top-right",
  "center-left",
  "center",
  "center-right",
  "bottom-left",
  "bottom",
  "bottom-right",
}) do
  M.POSITIONS[#M.POSITIONS + 1] = name
end

--- Determine the cell box inside a window at a named position.
--- `position = "full"` ignores `scale` (always 1); every other position uses
--- `scale` (default `M.DEFAULT_ANCHOR_SCALE`) and centres the resulting box on
--- its anchor rather than gluing it into a corner — so "top-right" sits
--- centred against the top right edge, not flush in the corner.
---@param win_width integer cells
---@param win_height integer cells
---@param position string one of `M.POSITIONS`
---@param scale number|nil 0 < scale <= 1; ignored for `position = "full"`
---@return integer|nil cols, integer|nil rows, integer|nil col_offset, integer|nil row_offset, string|nil err
function M.anchor_box(win_width, win_height, position, scale)
  local anchor = ANCHORS[position]
  if not anchor then
    return nil, nil, nil, nil, ("unknown position: %s (expected %s)"):format(tostring(position), table.concat(M.POSITIONS, "|"))
  end

  local effective_scale = (position == "full") and 1 or math.max(0.05, math.min(1, scale or M.DEFAULT_ANCHOR_SCALE))

  local cols = math.max(1, math.floor(win_width * effective_scale))
  local rows = math.max(1, math.floor(win_height * effective_scale))
  local col_offset = math.floor((win_width - cols) * anchor.h)
  local row_offset = math.floor((win_height - rows) * anchor.v)
  return cols, rows, col_offset, row_offset, nil
end

--- The cell box an image is really drawn in, inside a window's content area:
--- `M.anchor_box`, then the `margin` kept free all round, then the box fitted to
--- the picture's own aspect ratio and centred. `images.anchor` draws exactly here,
--- and anything that maps a screen cell back onto the picture (`images.viewport`)
--- reads the same box, so the two cannot drift apart.
---
--- The margin is capped per axis so that even a very small window keeps at least
--- one cell of image -- a margin that eats the image entirely would be worse than
--- none.
---
--- **The box the WINDOW offers is not the box the PICTURE wants**, and handing the
--- terminal the former and trusting `preserveAspectRatio=1` to letterbox inside it
--- is not enough. Measured in WezTerm with an A4 page (993x1404) in an 82x25
--- preview window: the picture is scaled to the requested WIDTH and its height
--- then follows from the aspect ratio -- 57 rows, ending 23 rows past the bottom
--- of a 40-row screen. An image reaching past the last row scrolls the whole
--- screen and takes Neovim's grid with it (see `images.terminal`'s module docs).
--- Shrinking the request to the picture's own aspect ratio first removes the
--- ambiguity: both axes are already right, so it no longer matters which one the
--- terminal chooses to honour. The letterbox is centred in the box the anchor
--- picked, which is where a terminal that fits properly would have put it anyway.
--- Without readable dimensions (SVG, an unknown container) `M.fit_cells` returns
--- the box unchanged, which is the older behaviour.
---@param win_width integer content cells
---@param win_height integer content cells
---@param position string one of `M.POSITIONS`
---@param scale number|nil see `M.anchor_box`
---@param margin integer cells kept free on every side, >= 0
---@param image_px Images.Scale.MaybeDims|nil
---@return integer|nil cols, integer|nil rows, integer|nil col_offset, integer|nil row_offset, string|nil err offsets 0-based from the content's top-left cell
function M.draw_box(win_width, win_height, position, scale, margin, image_px)
  local cols, rows, col_off, row_off, err = M.anchor_box(win_width, win_height, position, scale)
  if not (cols and rows and col_off and row_off) then return nil, nil, nil, nil, err end

  if margin > 0 then
    local mc = math.min(margin, math.floor((cols - 1) / 2))
    local mr = math.min(margin, math.floor((rows - 1) / 2))
    if mc > 0 then
      cols, col_off = cols - 2 * mc, col_off + mc
    end
    if mr > 0 then
      rows, row_off = rows - 2 * mr, row_off + mr
    end
  end

  local fit_cols, fit_rows = M.fit_cells(cols, rows, image_px)
  col_off = col_off + math.floor((cols - fit_cols) / 2)
  row_off = row_off + math.floor((rows - fit_rows) / 2)
  return fit_cols, fit_rows, col_off, row_off, nil
end

--- Assumed pixel aspect ratio of a terminal cell (width/height). images.nvim
--- never queries the terminal for it (the "no cell measurement" guardrail) —
--- 0.5 is a coarse assumption typical of common monospace fonts (a cell is
--- roughly twice as tall as it is wide). That is
--- enough for `M.fit_cells` to pick a draw box that `preserveAspectRatio=1`
--- has almost nothing left to letterbox.
---
--- Overwritten by `images.cell` as soon as `display.cell_aspect` supplies a
--- value. Without one the assumption stands — no caller has to tell the
--- difference.
M.CELL_ASPECT = 0.5

--- A configured `max_cols`/`max_rows`, made safe for every caller that reads
--- it straight off `display` (ERR-22): a non-number throws the moment it
--- reaches a comparison or multiplication (`M.fit_cells`'s own `cols <=
--- max_cols` included, once `image_px` is known), and a 0 or negative box is
--- a valid number that still crashes downstream — `nvim_open_win` rejects a
--- non-positive width/height outright (`hover_float.lua`'s `M.dimensions`).
--- `x or default` alone only substitutes on `nil`/`false`, not on either of
--- those, so callers that read `display.max_cols`/`max_rows` route it through
--- here before using it for anything, the same idiom as `images.pdf`'s
--- `M.page`/`M.dpi`.
---@param value any
---@param default integer
---@return integer
function M.valid_box(value, default)
  if type(value) == "number" and value == value and value >= 1 then return math.floor(value) end
  return default
end

--- Determine the draw box in cells that fills `image_px`'s aspect ratio
--- (expressed in cells via `M.CELL_ASPECT`) within the maximum size — the same
--- "fit to the longer axis" idea as any aspect-ratio fit, just with the
--- intermediate step from pixels to cells.
---
--- **Every draw goes through here, and that is not a presentation choice.**
--- OSC 1337's `preserveAspectRatio=1` only scales down to the box on the axis
--- that binds first; hand a terminal a box wider than the picture's ratio can
--- use and the height follows the width straight past the box — past the last
--- row, that scrolls the screen and takes Neovim's grid with it. Fitting first
--- makes both axes right, so which one the terminal honours stops mattering.
--- Without dimensions the box is returned unchanged, which is the older,
--- terminal-dependent behaviour and the best that can be done for a file that
--- does not say how big it is.
---@param max_cols integer
---@param max_rows integer
---@param image_px Images.Scale.MaybeDims|nil
---@return integer cols, integer rows
function M.fit_cells(max_cols, max_rows, image_px)
  -- Same reason as in `M.compute`: nil is the documented case, so it has to be
  -- checked before the comparison rather than by it.
  if not (image_px and image_px.width and image_px.height and image_px.width > 0 and image_px.height > 0) then
    return max_cols, max_rows
  end

  local image_aspect = image_px.width / image_px.height
  local cols = math.floor(max_rows * image_aspect / M.CELL_ASPECT)
  if cols <= max_cols then return math.max(1, cols), max_rows end

  local rows = math.floor(max_cols * M.CELL_ASPECT / image_aspect)
  return max_cols, math.max(1, rows)
end

return M
