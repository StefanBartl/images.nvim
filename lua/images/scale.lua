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

--- The same pair, both known -- what `M.cell_box_to_pixels` needs, because it
--- divides by them. Narrowed once at the place that checked, rather than
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

--- Assumed pixel aspect ratio of a terminal cell (width/height). images.nvim
--- never queries the terminal for it (the "no cell measurement" guardrail) —
--- 0.5 is a coarse assumption typical of common monospace fonts (a cell is
--- roughly twice as tall as it is wide). That is
--- enough for `images.redact`: `M.fit_cells` picks the draw box so that
--- `preserveAspectRatio=1` has almost nothing left to letterbox, and
--- `M.cell_box_to_pixels`'s safety margin absorbs the rest — better one cell
--- too much blacked out than one too little.
---
--- Overwritten by `images.cell` as soon as `display.cell_aspect` supplies a
--- value. Without one the assumption stands — no caller has to tell the
--- difference.
M.CELL_ASPECT = 0.5

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

--- Convert a 1-based, inclusive cell box (relative to the draw box) into a
--- pixel box of the source file. Assumes `draw_cols`/`draw_rows` were chosen
--- via `M.fit_cells` — otherwise the assumed 1:1 correspondence between cell
--- grid and visible image would be noticeably off. `padding_cells` grows the
--- box outwards before conversion: a redaction should err on the large side.
---@param box { row1: integer, col1: integer, row2: integer, col2: integer }
---@param draw_cols integer
---@param draw_rows integer
---@param image_px Images.Scale.Dims
---@param padding_cells integer|nil
---@return { x1: integer, y1: integer, x2: integer, y2: integer }
function M.cell_box_to_pixels(box, draw_cols, draw_rows, image_px, padding_cells)
  padding_cells = padding_cells or 0

  local col1 = math.max(1, box.col1 - padding_cells)
  local row1 = math.max(1, box.row1 - padding_cells)
  local col2 = math.min(draw_cols, box.col2 + padding_cells)
  local row2 = math.min(draw_rows, box.row2 + padding_cells)

  local scale_x = image_px.width / draw_cols
  local scale_y = image_px.height / draw_rows

  local x1 = math.floor((col1 - 1) * scale_x)
  local y1 = math.floor((row1 - 1) * scale_y)
  local x2 = math.ceil(col2 * scale_x)
  local y2 = math.ceil(row2 * scale_y)

  return {
    x1 = math.max(0, math.min(x1, image_px.width)),
    y1 = math.max(0, math.min(y1, image_px.height)),
    x2 = math.max(0, math.min(x2, image_px.width)),
    y2 = math.max(0, math.min(y2, image_px.height)),
  }
end

return M
