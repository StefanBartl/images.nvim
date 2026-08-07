---@module 'images.hover_float'
---@brief Bild in einem cursor-nahen Floating-Window statt über dem Text.
---@description
--- Alternative zum Standard-Modus ("draw over text", verschwindet bei
--- Cursorbewegung per `:mode`-Repaint, siehe `images.terminal`): ein echtes,
--- unfokussiertes Floating-Window unter dem Cursor. Dieselbe Technik wie
--- `images.zen` — Fenster öffnen, dann an dessen eigener Geometrie zeichnen
--- —, nur klein und cursor-positioniert statt zentriert und groß. Dass
--- diese Technik funktioniert, ist über `:Image zen` bereits belegt; hier
--- ändert sich nur die Positionierung und Größe, nicht das Grundprinzip.
---
--- Opt-in über `display.hover_mode = "float"` (default `"overlay"` — das
--- bisherige, bewährte Draw-over-text-Verhalten bleibt unverändert
--- Standard). `enter = false`/`focusable = false`: das Float stiehlt nicht
--- den Fokus und lässt sich nicht anklicken — anders als `images.zen`, das
--- bewusst fokussiert und editierbar ist. Ein Hover soll ein Blick sein,
--- kein Wechsel; es schließt automatisch beim nächsten
--- `display.clear_events`-Ereignis, ohne eigene `q`/`<Esc>`-Bindung, die an
--- einem unfokussierbaren Fenster ohnehin nie erreichbar wäre.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Aktuell offenes Hover-Fenster, falls eines besteht.
---@type integer|nil
local winid = nil

--- Ob gerade ein Hover-Float offen ist.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Hover-Fenster aktiv schließen (No-op, wenn keines offen ist).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then
    winid = nil
    require("images.terminal").clear()
  end
end

--- Fenstergeometrie ermitteln und das Bild dort zeichnen.
---
--- `vim.schedule` aus demselben Grund wie in `images.zen` (dort ausführlich
--- begründet): synchron gezeichnet läge das Bild vor Neovims Repaint des
--- gerade geöffneten Fensters und würde davon überdeckt.
---@param file string
---@return nil
local function redraw(file)
  vim.schedule(function()
    if not winid or not vim.api.nvim_win_is_valid(winid) then return end
    local pos = vim.api.nvim_win_get_position(winid)
    local width = vim.api.nvim_win_get_width(winid)
    local height = vim.api.nvim_win_get_height(winid)
    require("images.terminal").clear()
    local ok, err = require("images.terminal").draw(file, pos[1] + 1, pos[2] + 1, width, height)
    if not ok then notify().error(err or "Anzeige fehlgeschlagen") end
  end)
end

--- Fenstergröße bestimmen: `display.max_cols`/`max_rows`, gedeckelt auf die
--- tatsächliche Editorgröße. Reine Funktion (kein Fenster, keine
--- Seiteneffekte) — deshalb ohne Terminal testbar, wie `images.zen.dimensions`.
---@param display_cfg ImagesNvim.DisplayConfig
---@return integer width
---@return integer height
function M.dimensions(display_cfg)
  local width = math.min(display_cfg.max_cols, math.max(1, vim.o.columns - 4))
  local height = math.min(display_cfg.max_rows, math.max(1, vim.o.lines - 4))
  return width, height
end

--- Bild in einem Float unter dem Cursor anzeigen.
---@param file string Absoluter Pfad
---@return boolean ok
function M.open(file)
  M.close() -- ein bereits offenes Hover-Float ersetzen statt zu stapeln

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
    notify().error("Hover-Fenster konnte nicht geöffnet werden")
    return false
  end
  winid = win

  vim.api.nvim_create_autocmd("WinClosed", {
    group = vim.api.nvim_create_augroup("images.hover_float", { clear = true }),
    pattern = tostring(winid),
    once = true,
    callback = function()
      winid = nil
      require("images.terminal").clear()
    end,
    desc = "images.hover_float: Aufräumen beim Schließen",
  })

  redraw(file)
  return true
end

return M
