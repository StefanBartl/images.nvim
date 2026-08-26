---@module 'images.hover_float'
---@brief Show the image in a floating window near the cursor rather than over
--- the text.
---@description
--- The alternative to the default mode ("draw over text", cleared on cursor
--- movement by a `:mode` repaint, see `images.terminal`): a real, unfocused
--- floating window under the cursor. The same technique as `images.zen` — open
--- a window, then draw against its own geometry — only small and
--- cursor-positioned rather than centred and large. That the technique works
--- is already established by `:Image zen`; only position and size change here,
--- not the underlying principle.
---
--- Opt in via `display.hover_mode = "float"` (default `"overlay"` — the
--- established draw-over-text behaviour remains the default unchanged).
--- `enter = false`/`focusable = false`: the float does not steal focus and
--- cannot be clicked — unlike `images.zen`, which is deliberately focused and
--- editable. A hover should be a glance, not a switch; it closes automatically
--- on the next `display.clear_events` event, without a `q`/`<Esc>` binding of
--- its own that an unfocusable window could never reach anyway.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- The currently open hover window, if there is one.
---@type integer|nil
local winid = nil

--- Whether a hover float is currently open.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Close the hover window (a no-op when none is open).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then
    winid = nil
    require("images.terminal").clear()
  end
end

--- Draw the image into the hover window. `defer = true` for the same reason as
--- in `images.zen` — see `images.anchor`'s module docs.
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

--- Determine the window size: `display.max_cols`/`max_rows`, capped to the
--- actual editor size. A pure function (no window, no side effects) and
--- therefore testable without a terminal, like `images.zen.dimensions`.
---@param display_cfg ImagesNvim.DisplayConfig
---@return integer width
---@return integer height
function M.dimensions(display_cfg)
  local width = math.min(display_cfg.max_cols, math.max(1, vim.o.columns - 4))
  local height = math.min(display_cfg.max_rows, math.max(1, vim.o.lines - 4))
  return width, height
end

--- Show an image in a float under the cursor.
---@param file string absolute path
---@return boolean ok
function M.open(file)
  M.close() -- replace an already open hover float rather than stacking them

  local width, height = M.dimensions(cfg().display)

  local win, buf = require("lib.nvim.window.make_scratch")({
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    enter = false,
    focusable = false,
    border = "rounded",
  })
  if not win or not buf then
    notify().error("could not open the hover window")
    return false
  end
  winid = win

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    winid = nil
    require("images.terminal").clear()
  end, {
    group = autocmd.group("images.hover_float", true),
    pattern = tostring(winid),
    once = true,
    desc = "images.hover_float: clean up on close",
  })

  redraw(file)
  return true
end

return M
