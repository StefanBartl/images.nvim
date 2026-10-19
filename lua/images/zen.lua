---@module 'images.zen'
---@brief Full-screen display for a single image.
---@description
--- Unlike `images.show` (a short block below the cursor) this fills nearly the
--- whole editor. Deliberately an ordinary, editable window plus buffer via
--- `lib.nvim.window.make_scratch` — NOT `ui.kit.viewer`, which is
--- read-only and closes itself on losing focus. That auto-close behaviour is
--- precisely what is unwanted here: a snacks hover popup opens its own float
--- beside or over this one, and a window tied to focus loss would vanish the
--- moment it did. An ordinary window has no such lifecycle and stays put, no
--- matter what pops up next to it.
---
--- The image itself remains a terminal overlay, as everywhere in images.nvim
--- (see `images.terminal`) — the window only supplies the target coordinates,
--- via window geometry rather than cursor position.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- A configured fraction, made safe to multiply against `vim.o.columns`/
--- `vim.o.lines` below (ERR-22): a non-number `width`/`height` throws there
--- ("attempt to perform arithmetic on a ... value", reproduced with a string,
--- a boolean and a table) since `zen_cfg.width or 0.9` only substitutes the
--- default on `nil`/`false`, not on a wrong type. 0 and negative fractions
--- are left to `M.dimensions`'s own `math.max(1, ...)` clamp, same as before.
---@param value any
---@param default number
---@return number
local function valid_fraction(value, default)
  if type(value) == "number" and value == value then return value end
  return default
end

--- The currently open zen window, if there is one.
---@type integer|nil
local winid = nil

--- The image in the open zen window and the fractions its box was sized from.
--- `current_box` is what `M.resize` steps away from.
---@type string|nil
local current_file = nil
---@type { width: number, height: number }|nil
local current_box = nil

--- The size steps `M.resize` cycles through when the user configured none.
---@type { width: number, height: number }[]
local DEFAULT_SIZES = {
  { width = 0.66, height = 0.66 },
  { width = 0.9, height = 0.85 },
  { width = 1, height = 1 },
}

--- Redraw the image at the zen window's current geometry. Runs initially and
--- again on every resize, so the image follows the window. `defer = true`
--- because on the first call the window has only just been opened — see
--- `images.anchor`'s module docs for the reasoning.
---@param file string
---@return nil
local function redraw(file)
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  require("images.anchor").draw(winid, "full", file, {
    defer = true,
    on_done = function(ok, err)
      if not ok then notify().error(err or "could not display the image") end
    end,
  })
end

--- Compute the window size from the configured fractions. A pure function (no
--- window, no side effects) and therefore testable without a terminal, unlike
--- the rest of this module. This is the MAXIMUM box; `M.dimensions_for`
--- shrinks it to an image's aspect ratio where needed.
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return integer width
---@return integer height
function M.dimensions(zen_cfg)
  zen_cfg = zen_cfg or {}
  local width = math.max(1, math.floor(vim.o.columns * valid_fraction(zen_cfg.width, 0.9)))
  local height = math.max(1, math.floor(vim.o.lines * valid_fraction(zen_cfg.height, 0.85)))
  return width, height
end

--- Window size for ONE specific image: the maximum box from `M.dimensions`,
--- shrunk to the image's aspect ratio (`images.scale.fit_cells`, the same
--- function `images.redact` already uses for this). Without real pixel
--- dimensions (no ImageMagick, or a format `images.info` cannot read) the
--- maximum box stands — unchanged behaviour.
---
--- Why do this here rather than let `preserveAspectRatio=1` handle it alone:
--- a window wider or taller than the (scaled) image shows visible empty space,
--- and a window cut to fit never has to leave anything empty in the first
--- place. The stronger reason came later — a terminal handed a box the picture
--- cannot fill scales to the WIDTH and lets the height run past the box, which
--- past the last row scrolls the screen. `images.anchor` now fits the draw box
--- the same way for every caller, so this is belt and braces rather than the
--- only line of defence; shaping the window is still worth it, because an
--- empty strip inside a frame is a frame in the wrong shape.
---@param file string
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return integer width
---@return integer height
function M.dimensions_for(file, zen_cfg)
  local max_w, max_h = M.dimensions(zen_cfg)
  local px = require("images.info").collect(file)
  if not px or not px.width or not px.height then return max_w, max_h end
  return require("images.scale").fit_cells(max_w, max_h, px)
end

--- The configured size steps, without invalid entries; the defaults when none
--- is left.
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return { width: number, height: number }[]
local function valid_sizes(zen_cfg)
  local out = {}
  local sizes = zen_cfg and zen_cfg.sizes
  if type(sizes) == "table" then
    for _, s in ipairs(sizes) do
      if type(s) == "table" and type(s.width) == "number" and type(s.height) == "number" then
        out[#out + 1] = { width = s.width, height = s.height }
      end
    end
  end
  return #out > 0 and out or DEFAULT_SIZES
end

--- The size step after `box` in direction `dir`: the smallest step with a
--- larger area for `dir > 0`, the largest one with a smaller area for
--- `dir < 0`; nil when there is none. The steps need not be sorted, and `box`
--- need not be one of them (the window may have opened at a size of its own).
--- Pure, like `M.dimensions`.
---@param box { width: number, height: number }
---@param sizes { width: number, height: number }[]
---@param dir integer
---@return { width: number, height: number }|nil
function M.next_size(box, sizes, dir)
  local area = box.width * box.height
  local best, best_area
  for _, s in ipairs(sizes) do
    local a = s.width * s.height
    if dir > 0 and a > area + 1e-9 and (not best_area or a < best_area) then
      best, best_area = s, a
    elseif dir < 0 and a < area - 1e-9 and (not best_area or a > best_area) then
      best, best_area = s, a
    end
  end
  return best
end

--- Grow (`dir > 0`) or shrink (`dir < 0`) the open zen window to the next size
--- step (`display.zen.sizes`), re-centred, and draw the image again at the new
--- size. A no-op without an open window or at the last step in that direction.
---@param dir integer
---@return boolean changed
function M.resize(dir)
  if not M.is_open() or not current_file or not current_box then return false end
  local box = M.next_size(current_box, valid_sizes(cfg().display.zen), dir)
  if not box then return false end
  local width, height = M.dimensions_for(current_file, box)
  -- The same caps `lib.nvim.window.make_scratch` applies on open, so the
  -- full-screen step still leaves the border and the command line visible.
  width = math.min(width, require("lib.nvim.window.max_float_width")())
  height = math.min(height, math.max(1, vim.o.lines - 4))
  if not pcall(vim.api.nvim_win_set_config, winid, { width = width, height = height }) then return false end
  current_box = box
  require("lib.nvim.window.center")(winid)
  -- The previous, larger picture is still on the terminal around the window.
  require("images.terminal").clear()
  redraw(current_file)
  return true
end

--- Whether a zen window is currently open.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Close the zen window (a no-op when none is open).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  current_file, current_box = nil, nil
  if winid then
    winid = nil
    require("images.terminal").clear()
  end
end

--- Map the grow/shrink keys (`display.zen.keys`) in the zen buffer; `false`
--- or an empty list leaves a direction unmapped.
---@param buf integer
---@param keys table|nil
---@return nil
local function map_resize_keys(buf, keys)
  keys = type(keys) == "table" and keys or {}
  for name, dir in pairs({ grow = 1, shrink = -1 }) do
    local lhs = keys[name]
    if type(lhs) == "string" then lhs = { lhs } end
    if type(lhs) == "table" then
      for _, k in ipairs(lhs) do
        vim.keymap.set("n", k, function()
          M.resize(dir)
        end, { buffer = buf, nowait = true, desc = "images.zen: " .. name .. " the window" })
      end
    end
  end
end

--- Show the image under the cursor (or at `path`) full-screen.
---
--- `opts.width`/`opts.height` (fractions of the editor) open the window at a
--- size of its own instead of `display.zen.width`/`height`; `M.resize` steps
--- on from there through `display.zen.sizes`.
---@param path string|nil nil = the image under the cursor
---@param opts { width?: number, height?: number }|nil
---@return boolean ok
function M.open(path, opts)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image found")
    return false
  end

  require("images.guard").check()

  -- Replace an already open zen window rather than stacking them.
  M.close()

  local zen_cfg = cfg().display.zen or {}
  opts = opts or {}
  local box = {
    width = valid_fraction(opts.width, valid_fraction(zen_cfg.width, 0.9)),
    height = valid_fraction(opts.height, valid_fraction(zen_cfg.height, 0.85)),
  }
  local width, height = M.dimensions_for(file, box)

  local win, buf = require("lib.nvim.window.make_scratch")({
    width = width,
    height = height,
    modifiable = true,
    nice_quit = true,
    title = " " .. vim.fn.fnamemodify(file, ":t") .. " ",
  })
  if not win or not buf then
    notify().error("could not open the zen window")
    return false
  end
  winid = win
  current_file, current_box = file, box
  map_resize_keys(buf, zen_cfg.keys)

  local autocmd = require("lib.nvim.bindings.autocmd")
  local group = autocmd.group("images.zen", true)
  autocmd.create({ "WinResized", "VimResized" }, function()
    redraw(file)
  end, {
    group = group,
    desc = "images.zen: image follows the window size",
  })
  autocmd.create("WinClosed", function()
    winid = nil
    current_file, current_box = nil, nil
    require("images.terminal").clear()
  end, {
    group = group,
    pattern = tostring(winid),
    once = true,
    desc = "images.zen: clean up on close",
  })

  redraw(file)
  return true
end

return M
