---@module 'images.integrations.menu'
---@brief Context menu entries for nvzone/menu (a soft, opt-in integration).
---@description
--- images.nvim has no dependency on a menu plugin. It *supplies* a list of
--- entries in the shape nvzone/menu expects, built with the helpers from
--- `lib.nvim.contextmenu`, and a host — typically the user's own RightMouse
--- dispatcher — composes them into its own menu, e.g.:
--- >
---   local items = require("images.integrations.menu").items()
---   -- append/prepend `items` to your own menu, then menu.open(composed)
--- <
--- Bound to `keymaps.filetypes` (default markdown/vimwiki/norg/text) — the
--- same condition under which the buffer-local keys from
--- `images.bindings.keymaps` are registered at all. No pre-check for "is the
--- cursor really on an image": the underlying functions (hover/info/…) report
--- that themselves via notify, exactly as the double-click handler already
--- does. Opt out via `config.menu.enable`.

local contextmenu = require("lib.nvim.contextmenu")

local M = {}

---@internal
---@param ft string|nil
---@param fts string[]
---@return boolean
local function ft_allowed(ft, fts)
  if not ft or ft == "" then return false end
  for _, f in ipairs(fts) do
    if f == ft then return true end
  end
  return false
end

--- Build the images.nvim menu entries for `bufnr`.
--- Returns an empty list when the integration is disabled or the filetype is
--- not configured, so a host can splice it in with `vim.list_extend` without
--- further checks.
---@param bufnr? integer default: current buffer
---@return Lib.ContextMenu.Item[]
function M.items(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local cfg = require("images.config").get()
  local mcfg = cfg.menu or {}
  if mcfg.enable == false then return {} end

  local fts = (cfg.keymaps and cfg.keymaps.filetypes) or {}
  if not ft_allowed(vim.bo[bufnr].filetype, fts) then return {} end

  local km = cfg.keymaps or {}
  local images = require("images")
  local out = {}

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Show image under cursor", images.hover, km.show),
    contextmenu.entry(true, "  Gallery (every image in the buffer)", images.gallery, km.gallery),
    contextmenu.entry(true, "  Next image", function()
      images.step(1)
    end, km.next),
    contextmenu.entry(true, "  Previous image", function()
      images.step(-1)
    end, km.prev)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Paste image from clipboard", function()
      images.paste()
    end, km.paste),
    contextmenu.entry(true, "  Take a screenshot", images.screenshot, km.screenshot)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Show image info", function()
      images.info()
    end)
  )

  return out
end

--- Convenience: the images.nvim entries as a single nested submenu, for hosts
--- that prefer an "Images ▸" fly-out. Returns nil when there is nothing to
--- show.
---@param label? string submenu label (default "  Images")
---@param bufnr? integer
---@return Lib.ContextMenu.Item|nil
function M.submenu(label, bufnr)
  return contextmenu.submenu(label or "  Images", M.items(bufnr))
end

return M
