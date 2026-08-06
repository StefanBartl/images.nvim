---@module 'images.compare'
---@brief Zwei Bilder aus einem Scan nebeneinander vergleichen.
---@description
--- Dünner Adapter über `lib.nvim.ui.kit.compare` (siehe dort für den
--- SEARCH→MARKED→COMPARE-Ablauf): dieses Modul liefert nur die Bilderliste
--- (wiederverwendet aus `images.browse`, kein zweiter Scanner) und die
--- `render`-Funktion, die ein Bild in die Fenstergeometrie einer
--- `surface` zeichnet — exakt dieselbe Koordinatenrechnung wie die
--- Picker-Vorschau in `images.browse`.
---
--- Skalierung relativ zueinander (siehe `images.scale`): sobald beide Bilder
--- ihre echten Pixelmaße kennen (via `images.info`, braucht ImageMagick),
--- bekommt das kleinere eine proportional kleinere, zentrierte Box statt
--- seine ganze Pane zu füllen — sonst sähen ein Icon und ein großes Foto
--- gleich groß aus, nur weil beide Panes gleich groß sind. Der einzige Punkt
--- im `kit.compare`-Vertrag, an dem beide Bilder zugleich bekannt sind, ist
--- `on_compare(a, b)`, das genau dafür ergänzt wurde (siehe dort). Ohne
--- ImageMagick bleibt es beim bisherigen Verhalten: beide füllen ihre Pane.

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

  -- Von `on_compare` gefüllt, von `render` gelesen: der einzige Weg, einem
  -- einzelnen `render(item, surface)`-Aufruf mitzuteilen, wie sich `item` zu
  -- seinem Vergleichspartner verhält, den er selbst nicht kennt. Pfad statt
  -- Index als Schlüssel — robust, falls `kit.compare` künftig denselben
  -- Pfad zweimal im Ergebnis erlaubt.
  ---@type table<string, number>
  local pending_scale = {}

  ---@param item string absoluter Pfad
  ---@param surface Lib.UI.Kit.Surface
  local function render(item, surface)
    local factor = pending_scale[item]
    if not browse.draw_in_window(item, surface.winid, factor) then
      pcall(surface.set_title, surface, "(kann nicht gezeichnet werden)")
    end
  end

  ---@param a string absoluter Pfad
  ---@param b string absoluter Pfad
  local function on_compare(a, b)
    pending_scale = {}
    local info = require("images.info")
    local info_a = info.collect(a) -- err (2nd return) ist hier egal: fehlende Maße → scale.compute fällt auf 1/1 zurück
    local info_b = info.collect(b)
    -- `info.collect` liefert width/height nur mit ImageMagick; ohne bleibt
    -- `images.scale.compute` bei 1/1, also dem bisherigen Vollflächen-Verhalten.
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
    title = "Bilder vergleichen: " .. root,
    on_close = function()
      require("images.terminal").clear()
    end,
  })
end

return M
