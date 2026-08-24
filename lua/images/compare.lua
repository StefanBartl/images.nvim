---@module 'images.compare'
---@brief Compare two images from a scan side by side.
---@description
--- A thin adapter over `lib.nvim.ui.kit.compare` (see there for the
--- SEARCH->MARKED->COMPARE flow): this module supplies only the image list
--- (reused from `images.browse`, no second scanner) and the `render` function
--- that draws an image into a `surface`'s window geometry — exactly the same
--- coordinate arithmetic as the picker preview in `images.browse`.
---
--- Scaling relative to each other (see `images.scale`): as soon as both images
--- know their real pixel dimensions (via `images.info`, needs ImageMagick), the
--- smaller one gets a proportionally smaller, centred box instead of filling
--- its whole pane — otherwise an icon and a large photo would look the same
--- size merely because both panes are. The one point in the `kit.compare`
--- contract where both images are known at once is `on_compare(a, b)`, which
--- was added for exactly this (see there). Without ImageMagick the previous
--- behaviour stands: both fill their pane.

local M = {}

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Search for images below a scope and pick two of them to compare.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil for scope="path": the target directory
---@return nil
function M.open(scope, arg)
  local browse = require("images.browse")
  local root, err = browse.roots(scope, arg)
  if not root then
    notify().warn(err or "no root found")
    return
  end

  local files = browse.scan(root)
  if #files < 2 then
    notify().info("comparing needs at least two images, found: " .. #files)
    return
  end

  require("images.guard").check()

  ---@param item string absolute path
  ---@return string
  local function format_item(item)
    return item:sub(#root + 2)
  end

  -- Filled by `on_compare`, read by `render`: the only way to tell a single
  -- `render(item, surface)` call how `item` relates to its comparison partner,
  -- which it does not know itself. Keyed by path rather than index — robust
  -- should `kit.compare` ever allow the same path twice in a result.
  ---@type table<string, number>
  local pending_scale = {}

  ---@param item string absolute path
  ---@param surface Lib.UI.Kit.Surface
  local function render(item, surface)
    local factor = pending_scale[item]
    if not browse.draw_in_window(item, surface.winid, factor) then pcall(surface.set_title, surface, "(cannot be drawn)") end
  end

  ---@param a string absolute path
  ---@param b string absolute path
  local function on_compare(a, b)
    pending_scale = {}
    local info = require("images.info")
    local info_a = info.collect(a) -- err (2nd return) is irrelevant here: missing dimensions -> scale.compute falls back to 1/1
    local info_b = info.collect(b)
    -- `info.collect` returns width/height only with ImageMagick; without it
    -- `images.scale.compute` stays at 1/1, the previous full-pane behaviour.
    local result = require("images.scale").compute(info_a, info_b)
    pending_scale[a] = result.a
    pending_scale[b] = result.b
  end

  require("lib.nvim.ui.kit").compare({
    items = files,
    format_item = format_item,
    render = render,
    on_compare = on_compare,
    clear = function()
      require("images.terminal").clear()
    end,
    title = "Compare images: " .. root,
    on_close = function()
      require("images.terminal").clear()
    end,
  })
end

return M
