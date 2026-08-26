---@module 'images.zen'
---@brief Full-screen display for a single image.
---@description
--- Unlike `images.show` (a short block below the cursor) this fills nearly the
--- whole editor. Deliberately an ordinary, editable window plus buffer via
--- `lib.nvim.window.make_scratch` — NOT `lib.nvim.ui.kit.viewer`, which is
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

--- The currently open zen window, if there is one.
---@type integer|nil
local winid = nil

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
  local width = math.max(1, math.floor(vim.o.columns * (zen_cfg.width or 0.9)))
  local height = math.max(1, math.floor(vim.o.lines * (zen_cfg.height or 0.85)))
  return width, height
end

--- Window size for ONE specific image: the maximum box from `M.dimensions`,
--- shrunk to the image's aspect ratio (`images.scale.fit_cells`, the same
--- function `images.redact` already uses for this). Without real pixel
--- dimensions (no ImageMagick, or a format `images.info` cannot read) the
--- maximum box stands — unchanged behaviour.
---
--- Why do this here rather than let `preserveAspectRatio=1` handle it alone:
--- the terminal only scales WITHIN the cell box it was sent and leaves the
--- remainder empty — so a window wider or taller than the (scaled) image shows
--- visible empty space rather than an error. A window cut to fit never has to
--- leave anything empty in the first place.
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

--- Whether a zen window is currently open.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Close the zen window (a no-op when none is open).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then
    winid = nil
    require("images.terminal").clear()
  end
end

--- Show the image under the cursor (or at `path`) full-screen.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.open(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image found")
    return false
  end

  require("images.guard").check()

  -- Replace an already open zen window rather than stacking them.
  M.close()

  local width, height = M.dimensions_for(file, cfg().display.zen)

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
