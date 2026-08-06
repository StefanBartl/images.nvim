---@module 'images.compare'
---@brief Zwei Bilder aus einem Scan nebeneinander vergleichen.
---@description
--- Dünner Adapter über `lib.nvim.ui.kit.compare` (siehe dort für den
--- SEARCH→MARKED→COMPARE-Ablauf): dieses Modul liefert nur die Bilderliste
--- (wiederverwendet aus `images.browse`, kein zweiter Scanner) und die
--- `render`-Funktion, die ein Bild in die Fenstergeometrie einer
--- `surface` zeichnet — exakt dieselbe Koordinatenrechnung wie die
--- Picker-Vorschau in `images.browse`.

local M = {}

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Bilder unterhalb eines Scopes durchsuchen und zwei davon zum Vergleich
--- auswählen.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil bei scope="path": das Zielverzeichnis
---@return nil
function M.open(scope, arg)
  local browse = require("images.browse")
  local root, err = browse.roots(scope, arg)
  if not root then
    notify().warn(err or "Kein Root gefunden")
    return
  end

  local files = browse.scan(root)
  if #files < 2 then
    notify().info("Mindestens zwei Bilder nötig zum Vergleichen, gefunden: " .. #files)
    return
  end

  require("images.guard").check()

  ---@param item string absoluter Pfad
  ---@return string
  local function format_item(item)
    return item:sub(#root + 2)
  end

  ---@param item string absoluter Pfad
  ---@param surface Lib.UI.Kit.Surface
  local function render(item, surface)
    if not browse.draw_in_window(item, surface.winid) then pcall(surface.set_title, surface, "(kann nicht gezeichnet werden)") end
  end

  require("lib.nvim.ui.kit").compare({
    items = files,
    format_item = format_item,
    render = render,
    clear = function()
      require("images.terminal").clear()
    end,
    title = "Bilder vergleichen: " .. root,
    on_close = function()
      require("images.terminal").clear()
    end,
  })
end

return M
