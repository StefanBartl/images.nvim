---@module 'images.ascii'
---@brief Bild als farbige Blockgrafik zeichnen, wenn OSC 1337 nicht geht.
---@description
--- Fallback für jedes Terminal ohne Grafikprotokoll (SSH, tmux ohne
--- passthrough, ein nicht erkanntes Terminal) — siehe
--- docs/ROADMAP/CROSS-PLUGIN.md, Abschnitt color_my_ascii.nvim.
---
--- Ursprünglich als color_my_ascii.nvim-Integration angedacht. Dessen
--- Highlighter färbt aber bekannte ASCII-Zeichenklassen (Pfeile,
--- Box-Drawing, Operatoren, …) gegen ein benanntes Schema — Muster-basiert,
--- eine Farbe pro Klasse. Für ein Bild wird dagegen eine beliebige RGB-Farbe
--- pro Zelle gebraucht, die aus echten Pixeln kommt; das ist eine andere Art
--- Färbung, die color_my_ascii nicht anbietet. Deshalb hier ein eigener,
--- schlanker Pfad direkt über `nvim_set_hl`/Extmarks statt einer Abhängigkeit,
--- die nicht passt.
---
--- Braucht ImageMagick zwingend — die vierte bewusste Ausnahme neben SVG,
--- `:Image export` und `:Image redact` (siehe docs/ROADMAP/README.md):
--- Pixelfarben aus einer beliebigen Rasterdatei zu lesen braucht einen
--- echten Bild-Decoder, den reines Lua nicht hat.
---
--- Jede Terminalzelle wird ein "█"-Zeichen mit eigener Vordergrundfarbe —
--- Truecolor-Blockgrafik wie sie graphikprotokoll-lose Bildbetrachter
--- (chafa, viu) einsetzen, statt eines Helligkeits-Zeichensatzes
--- (" .:-=+*#%@"). Farbtreuer, ohne die Zusatzfrage "welches Zeichen für
--- welche Helligkeit".
---
--- Bewusst nur der Einzelbild-Pfad (`images.init.M.show`) — dieselbe
--- Scope-Grenze wie bei den Remote-Bildern (siehe images.remote): Galerie,
--- compare, pickers und zen bekommen das (noch) nicht.

local M = {}

local NS = vim.api.nvim_create_namespace("images.ascii")
local BLOCK = "█"

--- Aktuell offenes ASCII-Fenster, falls eines besteht.
---@type integer|nil
local winid = nil

---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Fenster aktiv schließen (No-op, wenn keines offen ist).
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  winid = nil
end

--- Ob ImageMagick verfügbar ist — die einzige Voraussetzung dieses Moduls.
---@return boolean
function M.available()
  return vim.fn.executable("magick") == 1
end

--- `path` auf `cols`x`rows` Pixel herunterrechnen und als rohe RGB-Bytes
--- zurücklesen, ein Tripel pro Zielzelle. `-resize WxH!` ignoriert das
--- Seitenverhältnis bewusst — die Zielgröße kommt bereits seitenverhältnis-
--- korrigiert aus `images.scale.fit_cells`, das Quetschen hier ist also
--- keine Verzerrung, sondern die letzte, bereits beabsichtigte Rundung.
---@param path string
---@param cols integer
---@param rows integer
---@return string|nil raw cols*rows*3 Bytes, zeilenweise RGB
---@return string|nil err
local function sample(path, cols, rows)
  local result = vim
    .system({
      "magick",
      path .. "[0]", -- erstes Frame bei Multi-Frame-Formaten (gif), wie images.info
      "-resize",
      cols .. "x" .. rows .. "!",
      "-alpha",
      "off", -- feste 3 Bytes/Pixel statt 4, kein Alpha-Sonderfall beim Auslesen
      "-depth",
      "8",
      "RGB:-",
    }, { text = false })
    :wait()

  if result.code ~= 0 then return nil, "ASCII-Sampling fehlgeschlagen: " .. vim.trim(tostring(result.stderr or "")) end
  local raw = result.stdout
  local need = cols * rows * 3
  if not raw or #raw < need then return nil, "ASCII-Sampling lieferte zu wenig Daten" end
  return raw
end

--- Hex-Farbe → Highlight-Gruppe, gecacht über die Sitzung. Der Gruppenname
--- kodiert die Farbe direkt, damit dieselbe Farbe nie zwei Gruppen bekommt.
---@type table<string, string>
local hl_cache = {}

---@param hex string "#rrggbb"
---@return string group
local function hl_group(hex)
  local group = hl_cache[hex]
  if not group then
    group = "ImagesAscii_" .. hex:sub(2)
    vim.api.nvim_set_hl(0, group, { fg = hex })
    hl_cache[hex] = group
  end
  return group
end

--- Bild als farbige Blockgrafik in einem Floating-Window unter dem Cursor
--- zeichnen.
---@param path string absoluter Pfad
---@param display ImagesNvim.DisplayConfig
---@return boolean ok
---@return string|nil err
function M.open(path, display)
  if not M.available() then return false, "ASCII-Fallback braucht ImageMagick (`magick` nicht gefunden)" end

  local info = require("images.info").collect(path)
  local image_px = (info and info.width and info.height) and { width = info.width, height = info.height } or nil
  local cols, rows = require("images.scale").fit_cells(display.max_cols, display.max_rows, image_px)

  local raw, err = sample(path, cols, rows)
  if not raw then return false, err end

  M.close()

  local lines = {}
  for _ = 1, rows do
    lines[#lines + 1] = BLOCK:rep(cols)
  end

  local win, buf = require("lib.nvim.window.make_scratch")({
    relative = "cursor",
    row = 1,
    col = 0,
    width = cols,
    height = rows,
    lines = lines,
    enter = false,
    focusable = false,
    border = "rounded",
    title = " ASCII (kein OSC 1337) ",
  })
  if not win or not buf then return false, "ASCII-Fenster konnte nicht geöffnet werden" end
  winid = win

  -- BLOCK ("█") ist 3 Bytes in UTF-8 — Byte-Spalten für die Extmark-Grenzen,
  -- nicht Anzeigespalten.
  for row = 1, rows do
    for col = 1, cols do
      local idx = ((row - 1) * cols + (col - 1)) * 3 + 1
      local r, g, b = raw:byte(idx), raw:byte(idx + 1), raw:byte(idx + 2)
      local hex = string.format("#%02x%02x%02x", r, g, b)
      vim.api.nvim_buf_set_extmark(buf, NS, row - 1, (col - 1) * 3, {
        end_col = col * 3,
        hl_group = hl_group(hex),
      })
    end
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = vim.api.nvim_create_augroup("images.ascii", { clear = true }),
    pattern = tostring(winid),
    once = true,
    callback = function()
      winid = nil
    end,
    desc = "images.ascii: Aufräumen beim Schließen",
  })

  return true
end

return M
