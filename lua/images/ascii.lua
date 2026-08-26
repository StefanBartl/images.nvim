---@module 'images.ascii'
---@brief Draw an image as coloured block graphics when OSC 1337 is
--- unavailable.
---@description
--- The fallback for any terminal without a graphics protocol (SSH, tmux
--- without passthrough, an unrecognised terminal) — see
--- docs/ROADMAP/CROSS-PLUGIN.md, section color_my_ascii.nvim.
---
--- Originally considered as a color_my_ascii.nvim integration. Its highlighter
--- colours known ASCII character classes (arrows, box drawing, operators, …)
--- against a named scheme — pattern-based, one colour per class. An image, by
--- contrast, needs an arbitrary RGB colour per cell derived from real pixels;
--- that is a different kind of colouring, and not one color_my_ascii offers.
--- Hence a small dedicated path straight over `nvim_set_hl`/extmarks instead of
--- a dependency that does not fit.
---
--- Requires ImageMagick — the fourth deliberate exception alongside SVG,
--- `:Image export` and `:Image redact` (see docs/ROADMAP/README.md): reading
--- pixel colours out of an arbitrary raster file needs a real image decoder,
--- which plain Lua does not have.
---
--- Every terminal cell becomes a "█" character with its own foreground colour —
--- truecolour block graphics as used by graphics-protocol-less image viewers
--- (chafa, viu), rather than a brightness character ramp (" .:-=+*#%@"). More
--- faithful to the colours, and without the extra question of "which character
--- for which brightness".
---
--- Deliberately the single-image path only (`images.init.M.show`) — the same
--- scope boundary as remote images (see images.remote): gallery, compare,
--- pickers and zen do not get this (yet).

local M = {}

local NS = vim.api.nvim_create_namespace("images.ascii")
local BLOCK = "█"

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
  return require("lib.nvim.cross.executable").exists("magick")
end

--- Downsample `path` to `cols`x`rows` pixels and read it back as raw RGB
--- bytes, one triple per target cell. `-resize WxH!` ignores the aspect ratio
--- deliberately — the target size already arrives aspect-corrected from
--- `images.scale.fit_cells`, so the squeeze here is not a distortion but the
--- final, already intended rounding.
---@param path string
---@param cols integer
---@param rows integer
---@return string|nil raw cols*rows*3 bytes, RGB row by row
---@return string|nil err
local function sample(path, cols, rows)
  local result = vim
    .system({
      "magick",
      path .. "[0]", -- first frame for multi-frame formats (gif), like images.info
      "-resize",
      cols .. "x" .. rows .. "!",
      "-alpha",
      "off", -- a fixed 3 bytes/pixel instead of 4, no alpha special case when reading
      "-depth",
      "8",
      "RGB:-",
    }, { text = false })
    :wait()

  if result.code ~= 0 then return nil, "ASCII sampling failed: " .. vim.trim(tostring(result.stderr or "")) end
  local raw = result.stdout
  local need = cols * rows * 3
  if not raw or #raw < need then return nil, "ASCII sampling returned too little data" end
  return raw
end

--- Hex colour -> highlight group, cached for the session. The group name
--- encodes the colour directly, so the same colour never gets two groups.
---@type table<string, string>
local hl_cache = {}

---@param hex string "#rrggbb"
---@return string group
local function hl_group(hex)
  local group = hl_cache[hex]
  if not group then
    group = "ImagesAscii_" .. hex:sub(2)
    vim.api.nvim_set_hl(0, group, { fg = hex })
    hl_cache[hex] = group
  end
  return group
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
  local cols, rows = require("images.scale").fit_cells(display.max_cols, display.max_rows, image_px)

  local raw, err = sample(path, cols, rows)
  if not raw then return false, err end

  M.close()

  local lines = {}
  for _ = 1, rows do
    lines[#lines + 1] = BLOCK:rep(cols)
  end

  local win, buf = require("lib.nvim.window.make_scratch")({
    relative = "cursor",
    row = 1,
    col = 0,
    width = cols,
    height = rows,
    lines = lines,
    enter = false,
    focusable = false,
    border = "rounded",
    title = " ASCII (no OSC 1337) ",
  })
  if not win or not buf then return false, "could not open the ASCII window" end
  winid = win

  -- BLOCK ("█") is 3 bytes in UTF-8 — byte columns for the extmark bounds, not
  -- display columns.
  for row = 1, rows do
    for col = 1, cols do
      local idx = ((row - 1) * cols + (col - 1)) * 3 + 1
      local r, g, b = raw:byte(idx), raw:byte(idx + 1), raw:byte(idx + 2)
      local hex = string.format("#%02x%02x%02x", r, g, b)
      vim.api.nvim_buf_set_extmark(buf, NS, row - 1, (col - 1) * 3, {
        end_col = col * 3,
        hl_group = hl_group(hex),
      })
    end
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
