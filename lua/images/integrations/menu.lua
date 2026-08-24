---@module 'images.integrations.menu'
---@brief Kontextmenü-Einträge für nvzone/menu (weiche, opt-in Integration).
---@description
--- images.nvim hat keine Abhängigkeit auf ein Menü-Plugin. Es *liefert*
--- eine Liste von Einträgen in der Form, die nvzone/menu erwartet, gebaut
--- mit den Helfern aus `lib.nvim.contextmenu`, und ein Host — typischerweise
--- der eigene RightMouse-Dispatcher des Nutzers — setzt sie zu seinem
--- eigenen Menü zusammen, z.B.:
--- >
---   local items = require("images.integrations.menu").items()
---   -- `items` an ein eigenes Menü an-/vorhängen, dann menu.open(composed)
--- <
--- Gebunden an `keymaps.filetypes` (default markdown/vimwiki/norg/text) —
--- dieselbe Bedingung, unter der die Buffer-lokalen Tasten aus
--- `images.bindings.keymaps` überhaupt registriert werden. Kein
--- Vor-Check auf "steht der Cursor wirklich auf einem Bild": die
--- unterliegenden Funktionen (hover/info/…) melden das selbst per
--- notify, genau wie der Doppelklick-Handler das schon tut. Opt-out über
--- `config.menu.enable`.

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

--- Baut die images.nvim-Menüeinträge für `bufnr`.
--- Liefert eine leere Liste, wenn die Integration deaktiviert ist oder der
--- Filetype nicht konfiguriert ist, sodass ein Host das bedenkenlos per
--- `vim.list_extend` einhängen kann.
---@param bufnr? integer Standard: aktueller Buffer
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
    contextmenu.entry(true, "  Bild unter Cursor anzeigen", images.hover, km.show),
    contextmenu.entry(true, "  Galerie (alle Bilder im Buffer)", images.gallery, km.gallery),
    contextmenu.entry(true, "  Nächstes Bild", function() images.step(1) end, km.next),
    contextmenu.entry(true, "  Vorheriges Bild", function() images.step(-1) end, km.prev)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Bild aus Zwischenablage einfügen", function() images.paste() end, km.paste),
    contextmenu.entry(true, "  Bildschirmausschnitt aufnehmen", images.screenshot, km.screenshot)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Bildinfo anzeigen", function() images.info() end)
  )

  return out
end

--- Komfort: die images.nvim-Einträge als ein einzelnes verschachteltes
--- Submenü, für Hosts, die ein "Images ▸"-Fly-out bevorzugen. Liefert nil,
--- wenn nichts anzuzeigen ist.
---@param label? string Submenü-Label (default "  Images")
---@param bufnr? integer
---@return Lib.ContextMenu.Item|nil
function M.submenu(label, bufnr)
  return contextmenu.submenu(label or "  Images", M.items(bufnr))
end

return M
