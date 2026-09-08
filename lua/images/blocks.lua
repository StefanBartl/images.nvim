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

--- The cell character. One "█" per cell, coloured by its own highlight group —
--- truecolour block graphics as chafa and viu draw them, rather than a
--- brightness ramp (" .:-=+*#%@").
M.BLOCK = "█"

--- Bytes per cell in the sampled payload: R, G, B with alpha turned off.
local BPP = 3

--- Steps per channel when a caller names none. See the module doc for why this
--- is a ceiling question rather than a quality one.
M.DEFAULT_LEVELS = 16

--- Quantised hex -> highlight group, for the session. Bounded by `levels³`,
--- which is what keeps this from being a leak.
---@type table<string, string>
local hl_cache = {}

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

--- The highlight group for one quantised colour, created on first use.
---@param hex string six hex digits, no leading "#"
---@return string group
local function hl_group(hex)
  local group = hl_cache[hex]
  if not group then
    group = "ImagesBlock_" .. hex
    vim.api.nvim_set_hl(0, group, { fg = "#" .. hex })
    hl_cache[hex] = group
  end
  return group
end

--- How many highlight groups this module has created so far. For health checks
--- and tests: the whole point of quantising is that this number stops growing.
---@return integer
function M.groups_created()
  return vim.tbl_count(hl_cache)
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
function M.sample_argv(paths, cols, rows)
  local argv = { "magick" }
  for _, path in ipairs(paths) do
    -- "[0]" is the first frame of a multi-frame format (gif), as images.info
    -- already does.
    argv[#argv + 1] = path .. "[0]"
  end
  argv[#argv + 1] = "-resize"
  argv[#argv + 1] = cols .. "x" .. rows .. "!"
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
  return cols * rows * BPP
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
--- on a timer. Adjacent cells of the same quantised colour share one extmark;
--- on flat material that is most of a row, on noisy material it changes
--- nothing, and it never costs more than the naive form.
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
    local run_start, run_hex = 0, nil
    for col = 0, cols - 1 do
      local i = base + (row * cols + col) * BPP + 1
      local hex = format(
        "%02x%02x%02x",
        quantise(byte(raw, i), levels),
        quantise(byte(raw, i + 1), levels),
        quantise(byte(raw, i + 2), levels)
      )
      if hex ~= run_hex then
        if run_hex then
          vim.api.nvim_buf_set_extmark(buf, ns, row, run_start * width, {
            end_col = col * width,
            hl_group = hl_group(run_hex),
          })
        end
        run_hex, run_start = hex, col
      end
    end
    if run_hex then
      vim.api.nvim_buf_set_extmark(buf, ns, row, run_start * width, {
        end_col = cols * width,
        hl_group = hl_group(run_hex),
      })
    end
  end

  return true, nil
end

return M
