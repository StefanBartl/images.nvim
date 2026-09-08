---@module 'images.blocks'
---@brief The block-graphics primitive: sample pixels into cells, and paint
--- those cells into a buffer somebody else owns.
---@description
--- Extracted out of `images.ascii`, which was the single-image, owns-its-own-
--- window version of this. Two things made a shared primitive worth having:
---
--- **A frame sequence has to be sampled in one process.** Measured
--- 2026-09-08 on 24 PNGs at 80x36 cells: **186 ms** for one `magick` call over
--- all of them, **1593 ms** for one call per file. A per-file loop is not a
--- slower version of playback — it is the reason there would be none.
---
--- **`nvim_set_hl` has a hard ceiling, and truecolour cells walk straight into
--- it.** Measured on this Neovim: **19 602 highlight groups** before `E849:
--- Too many highlight and syntax groups`, at ~0.08 ms per group. One
--- 80x36 frame has 2 880 cells; with a group per distinct colour, seven noisy
--- frames exhaust the session — permanently, since groups cannot be freed.
--- `images.ascii` has always had that fault latently (its cache is
--- session-wide and keyed by exact colour); it simply took an unusual number
--- of images to reach it. Quantising is therefore not a quality knob here but
--- the thing that makes the approach bounded: `levels` steps per channel caps
--- the group count at `levels³` no matter how many frames are drawn.
---
--- The default of 16 levels caps it at **4 096** — a fifth of the ceiling,
--- leaving the rest of the session's groups to the colourscheme and every
--- other plugin. In a picture made of 2 880 cells, the banding that costs is
--- not visible at cell resolution; a still that wants more can ask for it.
---
--- Drawing costs ~6.3 ms per 80x36 frame (2 880 extmarks, worst case: every
--- cell a different colour), so a 12 fps playback spends about 7% of its frame
--- budget on the paint. The expensive half was never the drawing.

local M = {}

--- The half block. **"▀", not "█"**: the upper half block carries the
--- foreground colour in its top half and the background colour in its bottom
--- half, so one text row shows *two* pixel rows. A full block wastes half of
--- every cell.
---
--- Kept as the name it always had, because `images.ascii` and the specs use
--- it, and because it is still the character the `half` geometry draws with.
M.BLOCK = "▀"

--- A text cell is about twice as tall as it is wide. Not a sub-pixel count --
--- the *shape* of a cell, which every aspect-ratio fit needs and no geometry
--- changes.
---
--- **These were one number until 2026-09-08, and they are not the same
--- number.** `ROWS_PER_CELL` meant both "sub-pixel rows in a cell" and "how
--- much taller a cell is than it is wide", which coincided exactly as long as
--- the half block was the only geometry. A sextant cell still has this shape;
--- it just divides it into three rows instead of two.
M.CELL_ASPECT = 2

-- **`ROWS_PER_CELL` is gone, deliberately.** It meant two things at once (see
-- `CELL_ASPECT` above) and, being a constant field, it could not follow the
-- configured geometry: once a cell can hold six sub-pixels it would still have
-- answered "2" to every caller sizing a payload, and a payload one third the
-- size it should be does not error -- it draws whatever the previous frame
-- left behind. `M.frame_bytes(cols, rows)` answers the size question and
-- `M.geometry().rows` the sub-pixel one.

--- One cell geometry: how a cell is divided, and what draws each pattern.
---
--- **Why more than one, and why this is where sharpness comes from.** A cell
--- can carry exactly two colours, no matter which character is in it — that is
--- a property of a terminal, not of the drawing. What a finer geometry buys is
--- not colour but *shape*: a half block can only say "top" and "bottom", so a
--- diagonal edge inside a cell is lost. A sextant divides the same cell into
--- six, so the edge survives even though the two colours do not change.
---
--- Measured 2026-09-08 on one 113x32-cell frame, counting cells that hold any
--- detail at all: 1 209 with half blocks, 2 108 with quadrants, 2 328 with
--- sextants. Reducing six sub-pixels to two colours costs **5.9 ms for a whole
--- 24-frame window** in LuaJIT — the clustering is not the expensive part, and
--- the expensive part (ImageMagick's startup) does not move.
---
--- `chars` is indexed by the bit pattern of which sub-pixels belong to the
--- brighter of the two colour clusters, bit `j * cols + i` for the sub-pixel
--- at column `i`, row `j`. `nil` means one character for every pattern, which
--- is the half block's special case: two sub-pixels are exactly a foreground
--- and a background, so nothing has to be chosen.
---@class Images.Blocks.Geometry
---@field name string
---@field cols integer sub-pixel columns in a cell
---@field rows integer sub-pixel rows in a cell
---@field chars string[]|nil 2^(cols*rows) characters, indexed by pattern + 1

---@internal
--- Sextant characters, U+1FB00..U+1FB3B, by bit pattern.
---
--- Unicode names them by the positions they fill, in the order
---
---     1 2
---     3 4
---     5 6
---
--- and assigns them in ascending pattern order — **skipping the four patterns
--- that already had characters**: 0 (space), 21 (left half), 42 (right half)
--- and 63 (full block). Getting that right matters more than it looks: 21 and
--- 42 are the vertical edges, which is the single most common pattern in real
--- footage, and an off-by-one here silently draws every one of them wrong.
---@return string[]
local function sextant_chars()
  local chars = {}
  local skipped = 0
  for pattern = 0, 63 do
    if pattern == 0 then
      -- Both clusters are the same colour whenever nothing is set, so the
      -- character is arbitrary; a full block keeps every entry the same width
      -- in cells and lets the background do the drawing.
      chars[pattern + 1] = "█"
      skipped = skipped + 1
    elseif pattern == 21 then
      chars[pattern + 1] = "▌"
      skipped = skipped + 1
    elseif pattern == 42 then
      chars[pattern + 1] = "▐"
      skipped = skipped + 1
    elseif pattern == 63 then
      chars[pattern + 1] = "█"
    else
      chars[pattern + 1] = vim.fn.nr2char(0x1FB00 + (pattern - skipped))
    end
  end
  return chars
end

--- The geometries this module can draw with.
---
--- `octant` (2x4, Unicode 16) is deliberately absent. It measured only
--- marginally better than sextants on real footage (2 421 detailed cells
--- against 2 328) and its block is from 2024 — a font or terminal without it
--- draws 256 replacement boxes, which is a far worse failure than the small
--- gain is a win.
---@type table<string, Images.Blocks.Geometry>
M.GEOMETRIES = {
  half = { name = "half", cols = 1, rows = 2, chars = nil },
  quadrant = {
    name = "quadrant",
    cols = 2,
    rows = 2,
    -- U+2596..U+259F plus the halves and the full block. Unicode 1.1, so
    -- there is no font in use anywhere that lacks these.
    chars = {
      "█", -- 0: one colour, character arbitrary
      "▘",
      "▝",
      "▀",
      "▖",
      "▌",
      "▞",
      "▛",
      "▗",
      "▚",
      "▐",
      "▜",
      "▄",
      "▙",
      "▟",
      "█",
    },
  },
  sextant = { name = "sextant", cols = 2, rows = 3, chars = sextant_chars() },
}

---@internal
--- The configured geometry, or the default when nothing is configured.
---
--- Read on every paint rather than cached: `:Image` can change it, and a paint
--- is 6 ms of work that will not notice a table lookup.
---@return Images.Blocks.Geometry
function M.geometry()
  local ok, config = pcall(require, "images.config")
  local name
  if ok and type(config.get) == "function" then
    local display = config.get().display or {}
    name = (display.ascii_fallback or {}).cells
  end
  return M.GEOMETRIES[name] or M.GEOMETRIES.sextant
end

--- Bytes per cell in the sampled payload: R, G, B with alpha turned off.
local BPP = 3

--- Steps per channel when a caller names none.
---
--- Eight rather than sixteen, because a half block's highlight group is a
--- *pair* of colours: the group count is bounded by the pairs that actually
--- occur, not by `levels³`. Measured on 24 frames of pure noise at 60x24
--- cells: 811 groups at 8 levels, and 5.4 ms to paint a frame. Real footage
--- repeats colours far more than noise does, so this is the pessimistic end.
M.DEFAULT_LEVELS = 8

--- Stop creating new groups here. Neovim's own ceiling is 19 602 (measured
--- 2026-09-08) and groups cannot be freed, so running into it would end the
--- session's colouring for everything, not just this. Past the budget the
--- palette collapses to 2 steps per channel — visibly worse, still drawing,
--- and impossible to walk into by accident since it needs thousands of
--- distinct colour pairs first.
local GROUP_BUDGET = 15000

--- Quantised colour pair -> highlight group, for the session.
---@type table<string, string>
local hl_cache = {}

--- How many groups this module has created. Watched against `GROUP_BUDGET`.
local created = 0

--- Whether ImageMagick is available — this module's only prerequisite.
---@return boolean
function M.available()
  return require("lib.nvim.cross.executable").exists("magick")
end

--- Snap one channel to `levels` evenly spaced steps, mapped back onto 0..255
--- so the brightest step is still white rather than `255 - 255/levels`.
---@param value integer 0..255
---@param levels integer
---@return integer
local function quantise(value, levels)
  if levels >= 256 then return value end
  local step = math.floor(value * levels / 256)
  if step >= levels then step = levels - 1 end
  return math.floor(step * 255 / (levels - 1) + 0.5)
end

--- The highlight group for one cell: `fg` is its upper pixel, `bg` its lower
--- one. Created on first use and kept for the session.
---@param fg string six hex digits, no leading "#"
---@param bg string six hex digits, no leading "#"
---@return string group
local function hl_group(fg, bg)
  local key = fg .. bg
  local group = hl_cache[key]
  if group then return group end

  if created >= GROUP_BUDGET then
    -- The budget is spent. Collapse to a palette so coarse that it cannot
    -- keep growing, rather than walking into E849 and taking every other
    -- plugin's highlights down with it.
    local function coarse(hex)
      local r = math.floor(tonumber(hex:sub(1, 2), 16) / 128) * 255
      local g = math.floor(tonumber(hex:sub(3, 4), 16) / 128) * 255
      local b = math.floor(tonumber(hex:sub(5, 6), 16) / 128) * 255
      return ("%02x%02x%02x"):format(r, g, b)
    end
    fg, bg = coarse(fg), coarse(bg)
    key = fg .. bg
    group = hl_cache[key]
    if group then return group end
  end

  group = "ImagesBlock_" .. key
  local ok = pcall(vim.api.nvim_set_hl, 0, group, { fg = "#" .. fg, bg = "#" .. bg })
  if not ok then
    -- E849 after all (another plugin spent the rest of the ceiling). Draw in
    -- whatever is already defined rather than erroring out of a redraw.
    return next(hl_cache) and hl_cache[next(hl_cache)] or "Normal"
  end
  hl_cache[key] = group
  created = created + 1
  return group
end

--- How many highlight groups this module has created so far. For health checks
--- and tests: the whole point of quantising is that this number stops growing.
---@return integer
function M.groups_created()
  return created
end

--- Cell size for an image inside a `max_cols` x `max_rows` box.
---
--- Not `images.scale.fit_cells`: that one assumes a cell holds *one* pixel and
--- corrects for a cell being about twice as tall as it is wide. A half block
--- puts two pixels in a cell, which makes those pixels square — so the fit is
--- a plain aspect fit against a `cols` x `rows * 2` pixel grid. Using the
--- other one here squashes every picture vertically by half.
---@param max_cols integer
---@param max_rows integer
---@param px { width: integer, height: integer }|nil
---@return integer cols, integer rows
function M.fit_cells(max_cols, max_rows, px)
  if not (px and px.width and px.height and px.width > 0 and px.height > 0) then return max_cols, max_rows end
  local aspect = px.width / px.height
  local rows = max_rows
  -- `CELL_ASPECT`, not the geometry's sub-pixel rows: this fits a picture into
  -- a grid of *cells*, and a cell is the same shape whether it is divided into
  -- two rows or three. Using the sub-pixel count here would stretch every
  -- picture by the ratio between the two.
  local cols = math.floor(rows * M.CELL_ASPECT * aspect)
  if cols > max_cols then
    cols = max_cols
    rows = math.floor(cols / aspect / M.CELL_ASPECT)
  end
  return math.max(1, cols), math.max(1, rows)
end

--- The `magick` argv that samples `paths` down to `cols`x`rows` cells each.
---
--- Public and pure so a test can assert the shape without running ImageMagick.
--- `-resize WxH!` ignores the aspect ratio deliberately: the target size
--- arrives aspect-corrected from `images.scale.fit_cells`, so the squeeze is
--- the intended final rounding, not a distortion.
---@param paths string[]
---@param cols integer
---@param rows integer
---@param geo Images.Blocks.Geometry|nil defaults to the configured one
---@return string[] argv
---
--- Both `cols` and `rows` are in **cells**; the pixel grid asked of
--- ImageMagick is `geo.cols` and `geo.rows` times that, because a cell holds
--- that many sub-pixels.
function M.sample_argv(paths, cols, rows, geo)
  local argv = { "magick" }
  for _, path in ipairs(paths) do
    -- "[0]" is the first frame of a multi-frame format (gif), as images.info
    -- already does.
    argv[#argv + 1] = path .. "[0]"
  end
  geo = geo or M.geometry()
  argv[#argv + 1] = "-resize"
  argv[#argv + 1] = (cols * geo.cols) .. "x" .. (rows * geo.rows) .. "!"
  -- A fixed 3 bytes per pixel: no alpha case when reading back.
  argv[#argv + 1] = "-alpha"
  argv[#argv + 1] = "off"
  argv[#argv + 1] = "-depth"
  argv[#argv + 1] = "8"
  argv[#argv + 1] = "RGB:-"
  return argv
end

--- Bytes one frame occupies in a sampled payload.
---
--- The one place that answers "how big is a frame". Every caller sizing or
--- validating a payload has to ask here rather than multiplying by a sub-pixel
--- count of its own: the count depends on the configured geometry, and a
--- payload sized for the wrong one is short, which draws the previous frame's
--- leftovers instead of failing.
---@param cols integer
---@param rows integer
---@param geo Images.Blocks.Geometry|nil defaults to the configured one
---@return integer
function M.frame_bytes(cols, rows, geo)
  geo = geo or M.geometry()
  return cols * geo.cols * rows * geo.rows * BPP
end

--- Sample every path in `paths` to `cols`x`rows` cells, in **one** ImageMagick
--- process, and hand back the raw RGB bytes for all of them concatenated.
---
--- Synchronous. The async form is `sample_async`; this one exists because the
--- single-image path (`images.ascii`) is called from a place that already
--- blocks and gains nothing from a callback.
---@param paths string[]
---@param cols integer
---@param rows integer
---@return string|nil raw  # #paths * cols * rows * 3 bytes
---@return string|nil err
function M.sample(paths, cols, rows)
  if type(paths) ~= "table" or #paths == 0 then return nil, "no paths to sample" end
  -- Resolved once and passed to both halves: the grid asked for and the size
  -- expected back have to be the same geometry's, and reading the
  -- configuration twice is a way for them not to be.
  local geo = M.geometry()
  local result = vim.system(M.sample_argv(paths, cols, rows, geo), { text = false }):wait()
  return M.read_sampled(result, #paths, cols, rows, geo)
end

--- Same, off the main loop. `callback` runs on the main loop exactly once.
---@param paths string[]
---@param cols integer
---@param rows integer
---@param callback fun(raw: string|nil, err: string|nil): nil
---@return nil
function M.sample_async(paths, cols, rows, callback)
  if type(paths) ~= "table" or #paths == 0 then
    vim.schedule(function()
      callback(nil, "no paths to sample")
    end)
    return
  end
  -- Once, before the process starts: this one spans an await, so a
  -- configuration change while ImageMagick runs would otherwise validate the
  -- answer against a geometry that was never asked for.
  local geo = M.geometry()
  vim.system(M.sample_argv(paths, cols, rows, geo), { text = false }, function(result)
    local raw, err = M.read_sampled(result, #paths, cols, rows, geo)
    vim.schedule(function()
      callback(raw, err)
    end)
  end)
end

--- Validate what `magick` wrote. Split out of both sample paths because "the
--- process succeeded but wrote too little" is the failure that matters here:
--- a short payload draws a frame of whatever the previous one left behind
--- rather than erroring, which is the kind of bug that looks like a decoder
--- problem for an hour.
---@param result vim.SystemCompleted
---@param count integer
---@param cols integer
---@param rows integer
---@param geo Images.Blocks.Geometry|nil the geometry the payload was asked for
---@return string|nil raw
---@return string|nil err
function M.read_sampled(result, count, cols, rows, geo)
  if result.code ~= 0 then return nil, "block sampling failed: " .. vim.trim(tostring(result.stderr or "")) end
  local raw = result.stdout
  local need = count * M.frame_bytes(cols, rows, geo)
  if not raw or #raw < need then return nil, ("block sampling returned %d of %d bytes"):format(raw and #raw or 0, need) end
  return raw, nil
end

--- The buffer lines a `cols`x`rows` canvas needs.
---
--- With half blocks every cell is the same character for the life of the
--- canvas and only highlights change per frame — that is what makes a 12 fps
--- repaint cheap, and it still holds. A finer geometry has to *choose* a
--- character per cell, so these lines are a correctly sized starting point
--- that `paint` overwrites; the caller's geometry (a float sized from these,
--- a `modifiable = false` buffer) is identical either way.
---@param cols integer
---@param rows integer
---@return string[]
function M.canvas_lines(cols, rows)
  local geo = M.geometry()
  local fill = geo.chars and geo.chars[#geo.chars] or M.BLOCK
  local lines = {}
  for _ = 1, rows do
    lines[#lines + 1] = fill:rep(cols)
  end
  return lines
end
---@internal
--- Paint one frame with the half block: the fast path, and the only geometry
--- where the buffer text never changes.
---
--- Two sub-pixels in a cell *are* a foreground and a background, so there is
--- nothing to choose and nothing to cluster — which is why this stayed a
--- separate function rather than becoming a one-cell case of the general one.
---@param buf integer
---@param ns integer
---@param raw string
---@param base integer byte offset of the frame in `raw`
---@param cols integer
---@param rows integer
---@param levels integer
---@return boolean ok
local function paint_half(buf, ns, raw, base, cols, rows, levels)
  local byte, format = string.byte, string.format
  -- BLOCK is 3 bytes in UTF-8, so extmark columns are byte columns.
  local width = #M.BLOCK

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row = 0, rows - 1 do
    local upper = base + (row * 2) * cols * BPP
    local lower = upper + cols * BPP
    local run_start, run_key, run_fg, run_bg = 0, nil, nil, nil
    for col = 0, cols - 1 do
      local u = upper + col * BPP + 1
      local l = lower + col * BPP + 1
      local fg = format(
        "%02x%02x%02x",
        quantise(byte(raw, u), levels),
        quantise(byte(raw, u + 1), levels),
        quantise(byte(raw, u + 2), levels)
      )
      local bg = format(
        "%02x%02x%02x",
        quantise(byte(raw, l), levels),
        quantise(byte(raw, l + 1), levels),
        quantise(byte(raw, l + 2), levels)
      )
      local key = fg .. bg
      if key ~= run_key then
        if run_key then
          vim.api.nvim_buf_set_extmark(buf, ns, row, run_start * width, {
            end_col = col * width,
            hl_group = hl_group(run_fg, run_bg),
          })
        end
        run_key, run_fg, run_bg, run_start = key, fg, bg, col
      end
    end
    if run_key then
      vim.api.nvim_buf_set_extmark(buf, ns, row, run_start * width, {
        end_col = cols * width,
        hl_group = hl_group(run_fg, run_bg),
      })
    end
  end
  return true
end

---@internal
--- The two colours one cell reduces to, and which sub-pixels took the brighter
--- of them.
---
--- **Shared, because `prepare` and `paint_cells` must agree exactly.** They
--- compute the same pairs for the same payload -- one to create the highlight
--- groups ahead of time, the other to look them up -- and a copy of this
--- arithmetic in each is a way for a paint to miss the cache and create a
--- group mid-frame, which is the full-screen redraw `prepare` exists to avoid.
---
--- Split at the midpoint of the cell's own luminance range: the cheap form of
--- what chafa does, and on a six-pixel cell the difference is not visible. A
--- flat cell collapses into one cluster, both colours come out the same, and
--- the pattern stops mattering -- correct, and needing no special case.
---@param raw string
---@param origin integer byte offset of the cell's first sub-pixel
---@param sx integer
---@param sy integer
---@param span integer bytes in one sub-pixel row of the whole canvas
---@param levels integer
---@return string fg, string bg, integer pattern
local function cell_colours(raw, origin, sx, sy, span, levels)
  local byte, format, floor = string.byte, string.format, math.floor

  local lmin, lmax = 1e9, -1e9
  for j = 0, sy - 1 do
    local o = origin + j * span
    for i = 0, sx - 1 do
      local p = o + i * BPP + 1
      local r, g, b = byte(raw, p, p + 2)
      local lum = r * 77 + g * 150 + b * 29
      if lum < lmin then lmin = lum end
      if lum > lmax then lmax = lum end
    end
  end

  local mid = (lmin + lmax) * 0.5
  local hr, hg, hb, hn = 0, 0, 0, 0
  local lr, lg, lb, ln = 0, 0, 0, 0
  local pattern = 0
  for j = 0, sy - 1 do
    local o = origin + j * span
    for i = 0, sx - 1 do
      local p = o + i * BPP + 1
      local r, g, b = byte(raw, p, p + 2)
      if r * 77 + g * 150 + b * 29 >= mid then
        hr, hg, hb, hn = hr + r, hg + g, hb + b, hn + 1
        pattern = pattern + 2 ^ (j * sx + i)
      else
        lr, lg, lb, ln = lr + r, lg + g, lb + b, ln + 1
      end
    end
  end
  if hn == 0 then
    hr, hg, hb, hn = lr, lg, lb, ln
  end
  if ln == 0 then
    lr, lg, lb, ln = hr, hg, hb, hn
  end

  -- Floored before quantising: `quantise` indexes a step table and a
  -- fractional channel would land between two of them.
  return format(
    "%02x%02x%02x",
    quantise(floor(hr / hn), levels),
    quantise(floor(hg / hn), levels),
    quantise(floor(hb / hn), levels)
  ),
    format("%02x%02x%02x", quantise(floor(lr / ln), levels), quantise(floor(lg / ln), levels), quantise(floor(lb / ln), levels)),
    pattern
end

---@internal
--- Paint one frame with a geometry finer than a half block.
---
--- **The two colours are found, not given.** A cell can hold two, and a
--- sextant has six sub-pixels to fit into them, so each cell's sub-pixels are
--- split at the midpoint of their own luminance range and averaged into a
--- bright cluster and a dark one. Which sub-pixels landed bright *is* the bit
--- pattern, and the pattern picks the character. Splitting at the midpoint
--- rather than running k-means is the cheap form of what chafa does, and on a
--- six-pixel cell the difference is not visible: measured 5.9 ms for a whole
--- 24-frame window at 113x32 cells.
---
--- A flat cell (every sub-pixel within a hair of the others) collapses to one
--- cluster, both colours become the same, and the character stops mattering —
--- which is the correct answer and needs no special case.
---
--- Unlike the half block this rewrites the line, because the characters are
--- the picture here. Byte offsets are accumulated per cell rather than
--- multiplied: the sextant block is 4 bytes but the left half, the right half
--- and the full block are 3, so a cell is not a fixed width in bytes and
--- assuming it is would put every highlight after the first such cell in the
--- wrong place.
---@param buf integer
---@param ns integer
---@param raw string
---@param base integer
---@param cols integer
---@param rows integer
---@param levels integer
---@param geo Images.Blocks.Geometry
---@return boolean ok
local function paint_cells(buf, ns, raw, base, cols, rows, levels, geo)
  local concat = table.concat
  local sx, sy, chars = geo.cols, geo.rows, geo.chars
  local span = cols * sx * BPP -- one sub-pixel row of the whole canvas

  local lines = {}
  ---@type table<integer, table[]>
  local marks = {}

  for row = 0, rows - 1 do
    local pieces, offs = {}, { [0] = 0 }
    local at = 0
    local run_start, run_key, run_fg, run_bg = 0, nil, nil, nil
    local row_marks = {}

    for col = 0, cols - 1 do
      local origin = base + (row * sy) * span + col * sx * BPP
      local fg, bg, pattern = cell_colours(raw, origin, sx, sy, span, levels)

      local char = chars[pattern + 1] or "█"
      pieces[#pieces + 1] = char
      at = at + #char
      offs[col + 1] = at

      -- A run is broken by a colour change *or* by nothing: unlike the half
      -- block, neighbouring cells with the same pair still need their own
      -- character, but they can share one extmark.
      local key = fg .. bg
      if key ~= run_key then
        if run_key then
          row_marks[#row_marks + 1] = { run_start = offs[run_start], stop = offs[col], fg = run_fg, bg = run_bg }
        end
        run_key, run_fg, run_bg, run_start = key, fg, bg, col
      end
    end
    if run_key then row_marks[#row_marks + 1] = { run_start = offs[run_start], stop = offs[cols], fg = run_fg, bg = run_bg } end

    lines[row + 1] = concat(pieces)
    marks[row] = row_marks
  end

  -- Text first, then highlights: `nvim_buf_set_lines` drops the extmarks in
  -- the lines it replaces, so painting before writing would paint nothing.
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  local ok = pcall(vim.api.nvim_buf_set_lines, buf, 0, rows, false, lines)
  vim.bo[buf].modifiable = modifiable
  if not ok then return false end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row = 0, rows - 1 do
    for _, mark in ipairs(marks[row]) do
      vim.api.nvim_buf_set_extmark(buf, ns, row, mark.run_start, {
        end_col = mark.stop,
        hl_group = hl_group(mark.fg, mark.bg),
      })
    end
  end
  return true
end

--- Create every highlight group a payload will need, before a single frame is
--- painted.
---
--- **This is a frame-rate fix, and the mechanism is not obvious.**
--- `nvim_set_hl` marks the whole screen invalid — Neovim has no way to know
--- which windows a redefined group appears in, so it redraws everything.
--- Creating groups lazily, from inside the paint, therefore costs one full
--- screen redraw per *new colour pair*, and a painted frame introduces plenty:
--- measured over eight seconds of real footage at 113x32 cells, between 10 and
--- 476 new groups per second, never settling, because every rolled window
--- brings new material. Headless that is invisible (nothing redraws) and the
--- paint measures 8 ms; in a terminal a reader reported **1-2 frames per
--- second**, which is what dozens of full redraws per frame look like.
---
--- Called once per decoded window, the same place and cadence the sampling
--- already runs at, the invalidations collapse into the one redraw that window
--- was going to cause anyway — and the paint itself then only ever looks
--- groups up.
---
--- Cheap enough to be unconditional: it is the clustering pass again, measured
--- at 5.9 ms for a 24-frame window, against a second of lead time the caller
--- already has.
---@param raw string the whole payload, every frame
---@param cols integer
---@param rows integer
---@param levels integer|nil
---@param geo Images.Blocks.Geometry|nil
---@return integer created  # groups this call added, for tests and health
function M.prepare(raw, cols, rows, levels, geo)
  levels = levels or M.DEFAULT_LEVELS
  geo = geo or M.geometry()
  local before = created
  local stride = M.frame_bytes(cols, rows, geo)
  local frames = math.floor(#raw / stride)
  local byte, format, floor = string.byte, string.format, math.floor
  local sx, sy = geo.cols, geo.rows
  local span = cols * sx * BPP

  for frame = 0, frames - 1 do
    local base = frame * stride
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        local origin = base + (row * sy) * span + col * sx * BPP
        if geo.chars then
          local fg, bg = cell_colours(raw, origin, sx, sy, span, levels)
          hl_group(fg, bg)
        else
          local u = origin + 1
          local l = origin + span + 1
          hl_group(
            format(
              "%02x%02x%02x",
              quantise(byte(raw, u), levels),
              quantise(byte(raw, u + 1), levels),
              quantise(byte(raw, u + 2), levels)
            ),
            format(
              "%02x%02x%02x",
              quantise(byte(raw, l), levels),
              quantise(byte(raw, l + 1), levels),
              quantise(byte(raw, l + 2), levels)
            )
          )
        end
      end
    end
  end
  local _ = floor
  return created - before
end

--- Paint frame `index` (1-based) of `raw` into `buf`, in namespace `ns`.
---
--- The buffer's lines must already be `canvas_lines(cols, rows)`. With half
--- blocks this only ever touches highlights, which is what makes repainting
--- cheap enough to do on a timer; a finer geometry also rewrites the text,
--- because there the characters *are* the picture. Adjacent cells of the same
--- colour pair share one extmark either way — on flat material that is most of
--- a row, on noisy material it changes nothing, and it never costs more than
--- the naive form.
---@param buf integer
---@param ns integer
---@param raw string
---@param index integer 1-based frame index into `raw`
---@param cols integer
---@param rows integer
---@param levels integer|nil steps per channel (default `DEFAULT_LEVELS`)
---@return boolean ok
---@return string|nil err
function M.paint(buf, ns, raw, index, cols, rows, levels)
  if not vim.api.nvim_buf_is_valid(buf) then return false, "buffer is gone" end
  levels = levels or M.DEFAULT_LEVELS
  local stride = M.frame_bytes(cols, rows)
  local base = (math.max(1, index) - 1) * stride
  if #raw < base + stride then return false, ("frame %d is past the end of the payload"):format(index) end

  local geo = M.geometry()
  if not geo.chars then return paint_half(buf, ns, raw, base, cols, rows, levels), nil end
  if not paint_cells(buf, ns, raw, base, cols, rows, levels, geo) then
    return false, "the canvas buffer refused the frame's lines"
  end
  return true, nil
end

return M
