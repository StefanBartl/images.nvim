---@module 'images.zen'
---@brief Vollbild-Anzeige für ein einzelnes Bild.
---@description
--- Anders als `images.show` (kurzer Block unterhalb des Cursors) füllt dies
--- fast den ganzen Editor. Bewusst ein normales, editierbares Fenster+Buffer
--- über `lib.nvim.window.make_scratch` — NICHT `lib.nvim.ui.kit.viewer`, das
--- read-only ist und beim Fokusverlust automatisch schließt. Genau dieses
--- Auto-Close-Verhalten ist hier unerwünscht: ein snacks-Hover-Popup öffnet
--- ein eigenes Float daneben/darüber, und ein an Fokusverlust gekoppeltes
--- Fenster würde dabei sofort verschwinden. Ein gewöhnliches Fenster hat
--- keinen solchen Lifecycle und bleibt bestehen, egal was daneben aufpoppt.
---
--- Das Bild selbst bleibt ein Terminal-Overlay wie überall in images.nvim
--- (siehe `images.terminal`) — das Fenster liefert nur die Zielkoordinaten,
--- über die Fenstergeometrie statt über die Cursorposition.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Aktuell offenes Zen-Fenster, falls eines besteht.
---@type integer|nil
local winid = nil

--- Das Bild neu zeichnen, an der aktuellen Geometrie des Zen-Fensters. Läuft
--- initial und erneut bei jeder Größenänderung, damit das Bild dem Fenster
--- folgt. `defer = true`, weil das Fenster beim ersten Aufruf gerade erst
--- geöffnet wurde — siehe `images.anchor`s Moduldoku für die Begründung.
---@param file string
---@return nil
local function redraw(file)
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  require("images.anchor").draw(winid, "full", file, {
    defer = true,
    on_done = function(ok, err)
      if not ok then notify().error(err or "Anzeige fehlgeschlagen") end
    end,
  })
end

--- Fenstergröße aus der Config-Anteilsangabe berechnen. Reine Funktion (kein
--- Fenster, keine Seiteneffekte) — deshalb ohne Terminal testbar, anders als
--- der Rest dieses Moduls.
---@param zen_cfg ImagesNvim.ZenConfig|nil
---@return integer width
---@return integer height
function M.dimensions(zen_cfg)
  zen_cfg = zen_cfg or {}
  local width = math.max(1, math.floor(vim.o.columns * (zen_cfg.width or 0.9)))
  local height = math.max(1, math.floor(vim.o.lines * (zen_cfg.height or 0.85)))
  return width, height
end

--- Ob gerade ein Zen-Fenster offen ist.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Zen-Fenster aktiv schließen (No-op, wenn keines offen ist).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then
    winid = nil
    require("images.terminal").clear()
  end
end

--- Bild unter dem Cursor (oder an `path`) im Vollbild anzeigen.
---@param path string|nil nil = Bild unter dem Cursor
---@return boolean ok
function M.open(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("Kein Bild gefunden")
    return false
  end

  require("images.guard").check()

  -- Ein bereits offenes Zen-Fenster ersetzen statt zu stapeln.
  M.close()

  local width, height = M.dimensions(cfg().display.zen)

  local win, buf = require("lib.nvim.window.make_scratch")({
    width = width,
    height = height,
    modifiable = true,
    nice_quit = true,
    title = " " .. vim.fn.fnamemodify(file, ":t") .. " ",
  })
  if not win or not buf then
    notify().error("Zen-Fenster konnte nicht geöffnet werden")
    return false
  end
  winid = win

  local autocmd = require("lib.nvim.autocmd")
  local group = autocmd.group("images.zen", true)
  autocmd.create({ "WinResized", "VimResized" }, function()
    redraw(file)
  end, {
    group = group,
    desc = "images.zen: Bild folgt der Fenstergröße",
  })
  autocmd.create("WinClosed", function()
    winid = nil
    require("images.terminal").clear()
  end, {
    group = group,
    pattern = tostring(winid),
    once = true,
    desc = "images.zen: Aufräumen beim Schließen",
  })

  redraw(file)
  return true
end

return M
