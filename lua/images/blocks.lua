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

--- The cell character. **"▀", not "█"**: the upper half block carries the
--- foreground colour in its top half and the background colour in its bottom
--- half, so one text row shows *two* pixel rows. Same cell count, twice the
--- vertical resolution, and it is what chafa and viu draw with for exactly
--- this reason. A full block wastes half of every cell.
M.BLOCK = "▀"

--- Pixel rows one text row carries. The consequence of the half block, and
--- the number every size calculation here has to know about.
M.ROWS_PER_CELL = 2

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
  local cols = math.floor(rows * M.ROWS_PER_CELL * aspect)
  if cols > max_cols then
    cols = max_cols
    rows = math.floor(cols / aspect / M.ROWS_PER_CELL)
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
---@return string[] argv
---
--- `rows` is in **cells**; the pixel grid asked of ImageMagick is twice as
--- tall, because of the half block.
function M.sample_argv(paths, cols, rows)
  local argv = { "magick" }
  for _, path in ipairs(paths) do
    -- "[0]" is the first frame of a multi-frame format (gif), as images.info
    -- already does.
    argv[#argv + 1] = path .. "[0]"
  end
  argv[#argv + 1] = "-resize"
  argv[#argv + 1] = cols .. "x" .. (rows * M.ROWS_PER_CELL) .. "!"
  -- A fixed 3 bytes per pixel: no alpha case when reading back.
  argv[#argv + 1] = "-alpha"
  argv[#argv + 1] = "off"
  argv[#argv + 1] = "-depth"
  argv[#argv + 1] = "8"
  argv[#argv + 1] = "RGB:-"
  return argv
end

--- Bytes one frame occupies in a sampled payload.
---@param cols integer
---@param rows integer
---@return integer
function M.frame_bytes(cols, rows)
  return cols * rows * M.ROWS_PER_CELL * BPP
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
  local result = vim.system(M.sample_argv(paths, cols, rows), { text = false }):wait()
  return M.read_sampled(result, #paths, cols, rows)
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
  vim.system(M.sample_argv(paths, cols, rows), { text = false }, function(result)
    local raw, err = M.read_sampled(result, #paths, cols, rows)
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
---@return string|nil raw
---@return string|nil err
function M.read_sampled(result, count, cols, rows)
  if result.code ~= 0 then return nil, "block sampling failed: " .. vim.trim(tostring(result.stderr or "")) end
  local raw = result.stdout
  local need = count * M.frame_bytes(cols, rows)
  if not raw or #raw < need then return nil, ("block sampling returned %d of %d bytes"):format(raw and #raw or 0, need) end
  return raw, nil
end

--- The buffer lines a `cols`x`rows` canvas needs: every cell is the same
--- character, and only the highlights change per frame.
---@param cols integer
---@param rows integer
---@return string[]
function M.canvas_lines(cols, rows)
  local lines = {}
  for _ = 1, rows do
    lines[#lines + 1] = M.BLOCK:rep(cols)
  end
  return lines
end

--- Paint frame `index` (1-based) of `raw` into `buf`, in namespace `ns`.
---
--- The buffer's lines must already be `canvas_lines(cols, rows)` — this only
--- ever touches highlights, which is what makes repainting cheap enough to do
--- on a timer. Adjacent cells of the same colour *pair* share one extmark; on
--- flat material that is most of a row, on noisy material it changes nothing,
--- and it never costs more than the naive form.
---
--- One text row is two pixel rows: the row's upper pixels become the cells'
--- foreground and the lower ones their background, which is what `▀` draws.
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

  local byte, format = string.byte, string.format
  -- BLOCK is 3 bytes in UTF-8, so extmark columns are byte columns.
  local width = #M.BLOCK

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row = 0, rows - 1 do
    local upper = base + (row * M.ROWS_PER_CELL) * cols * BPP
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

  return true, nil
end

return M
