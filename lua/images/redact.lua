---@module 'images.redact'
---@brief Zensur-Modus: Bild in einem Zen-artigen Fenster schwärzen, Original bleibt.
---@description
--- Konzept: docs/ROADMAP/REDACT.md. Motivation: casedesk-Anhänge (Screenshots
--- mit Kundendaten in `Ressources/`), die vor einer künftigen KI-Übergabe
--- unkenntlich gemacht werden müssen können.
---
--- Die eigentliche Hürde ist, dass ein per OSC 1337 gezeichnetes Bild für
--- Neovim nicht interaktiv ist — Maus/Cursor liefern nur Zellkoordinaten,
--- nie Pixelkoordinaten im Bild. Die Lösung hier: die Auswahl selbst passiert
--- komplett in Zellen, über echten Neovim-Visual-Mode auf einem mit
--- Leerzeichen gefüllten Scratch-Buffer in Bildgröße (`v`/`<C-v>` + `<CR>`
--- markiert eine Box, dieselbe Idee wie Visual-Block) — kein neues
--- Eingabe-System, keine Pixelmathematik während der Auswahl. Erst beim
--- Schreiben (`w`) wird einmalig umgerechnet: `images.scale.fit_cells` wählt
--- die Zeichenbox so, dass `preserveAspectRatio=1` kaum noch etwas zu
--- letterboxen hat (die Zellzahl wird an das Bildseitenverhältnis über eine
--- angenommene, dokumentierte Zellbreite/-höhe angepasst, `images.scale.
--- CELL_ASPECT` — keine echte Zellmessung, siehe dort), und `images.scale.
--- cell_box_to_pixels` rechnet mit einer Sicherheitsmarge in Pixelkoordinaten
--- um. Gebrannt wird über `images.convert.redact` (ImageMagick, dritte
--- bewusste Ausnahme von der "kein ImageMagick als Pflicht"-Leitplanke neben
--- SVG-Anzeige und `:Image export`).
---
--- **Nicht Teil der automatisierten Testsuite**: die Tastenlogik selbst
--- (Visual-Mode-Erfassung, Fensteraufbau) braucht ein echtes Terminal mit
--- OSC-1337-Unterstützung, um wirklich verifiziert zu werden — wie überall
--- in dieser Suite bleibt "Zeichnen" ungeprüft (siehe TESTS/zen_spec.lua).
--- Die reine Geometrie (`images.scale.fit_cells`/`cell_box_to_pixels`) und
--- das Brennen (`images.convert.redact`) sind dagegen getestet.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@type integer|nil
local winid = nil
---@type integer|nil
local bufnr = nil
---@type string|nil
local file = nil
---@type Images.Scale.Dims|nil
local image_px = nil
---@type integer
local draw_cols = 0
---@type integer
local draw_rows = 0

---@class Images.Redact.Box
---@field row1 integer
---@field col1 integer
---@field row2 integer
---@field col2 integer

---@type Images.Redact.Box[]
local boxes = {}

local ns = vim.api.nvim_create_namespace("images.redact")

--- Ob gerade ein Redact-Fenster offen ist.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Redact-Fenster aktiv schließen (No-op, wenn keines offen ist). Verwirft
--- unbestätigte Boxen — Original wie Zieldatei sind zu diesem Zeitpunkt
--- ohnehin unangetastet, nur `w` schreibt tatsächlich.
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then require("images.terminal").clear() end
  winid, bufnr, file, image_px, draw_cols, draw_rows = nil, nil, nil, nil, 0, 0
  boxes = {}
end

---@return nil
local function redraw_boxes()
  if not bufnr then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, box in ipairs(boxes) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, box.row1 - 1, box.col1 - 1, {
      end_row = box.row2 - 1,
      end_col = box.col2,
      hl_group = "Visual",
    })
  end
end

---@return nil
local function undo_box()
  if #boxes == 0 then
    notify().warn("Keine Box zum Entfernen")
    return
  end
  table.remove(boxes)
  redraw_boxes()
  notify().info(("Box entfernt (%d verbleiben)"):format(#boxes))
end

--- Die aktuelle Visual-Selektion als Redaktionsbox übernehmen. Läuft als
--- Visual-Mode-Mapping — `getpos("v")`/`getpos(".")` sind während der
--- Callback-Ausführung noch gültig, danach verlässt ein `<Esc>` den Modus.
---@return nil
local function confirm_box()
  local vstart = vim.fn.getpos("v")
  local vend = vim.fn.getpos(".")
  vim.cmd("normal! \27")

  local row1, col1 = vstart[2], vstart[3]
  local row2, col2 = vend[2], vend[3]
  if row1 > row2 then
    row1, row2 = row2, row1
  end
  if col1 > col2 then
    col1, col2 = col2, col1
  end

  boxes[#boxes + 1] = { row1 = row1, col1 = col1, row2 = row2, col2 = col2 }
  redraw_boxes()
  notify().info(("Box %d markiert"):format(#boxes))
end

---@return nil
local function write_redacted()
  if #boxes == 0 then
    notify().warn("Keine Box markiert — nichts zu schwärzen")
    return
  end
  if not file or not image_px then return end

  local padding = cfg().display.redact.padding_cells or 0
  local pixel_boxes = {}
  for _, box in ipairs(boxes) do
    pixel_boxes[#pixel_boxes + 1] = require("images.scale").cell_box_to_pixels(box, draw_cols, draw_rows, image_px, padding)
  end

  local out, err = require("images.convert").redact(file, pixel_boxes)
  if not out then
    notify().error(err or "Schwärzen fehlgeschlagen")
    return
  end

  notify().info("Geschwärzte Kopie gespeichert: " .. vim.fn.fnamemodify(out, ":~"))
  M.close()
end

--- Bild — oder das unter dem Cursor — im Zensur-Modus öffnen.
---@param path string|nil nil = Bild unter dem Cursor
---@return boolean ok
function M.open(path)
  local target = require("images.resolve").path_or_cursor(path)
  if not target then
    notify().warn("Kein Bild unter dem Cursor oder am angegebenen Pfad")
    return false
  end

  local px, info_err = require("images.info").collect(target)
  if not px or not px.width or not px.height then
    notify().error(info_err or "Bildmaße nicht ermittelbar — `:Image redact` braucht ImageMagick")
    return false
  end

  require("images.guard").check()
  M.close()

  local max_cols, max_rows = require("images.zen").dimensions(cfg().display.zen)
  local cols, rows = require("images.scale").fit_cells(max_cols, max_rows, px)

  local lines = {}
  local blank = (" "):rep(cols)
  for i = 1, rows do
    lines[i] = blank
  end

  local win, buf = require("lib.nvim.window.make_scratch")({
    lines = lines,
    width = cols,
    height = rows,
    modifiable = false,
    nice_quit = true,
    title = " Redact: " .. vim.fn.fnamemodify(target, ":t") .. " ",
  })
  if not win or not buf then
    notify().error("Redact-Fenster konnte nicht geöffnet werden")
    return false
  end

  winid, bufnr, file, image_px, draw_cols, draw_rows = win, buf, target, px, cols, rows
  boxes = {}

  local map = require("lib.nvim.map")
  map("n", "w", write_redacted, { buffer = buf, nowait = true }, "images.redact: schwärzen und speichern")
  map("n", "u", undo_box, { buffer = buf, nowait = true }, "images.redact: letzte Box entfernen")
  map("x", "<CR>", confirm_box, { buffer = buf, nowait = true }, "images.redact: Auswahl als Box markieren")

  local autocmd = require("lib.nvim.autocmd")
  autocmd.create("WinClosed", function()
    winid = nil
    require("images.terminal").clear()
  end, {
    group = autocmd.group("images.redact", true),
    pattern = tostring(win),
    once = true,
    desc = "images.redact: Aufräumen beim Schließen",
  })

  -- `defer = true` aus demselben Grund wie in `images.zen` — siehe
  -- `images.anchor`s Moduldoku: das Fenster wurde gerade erst geöffnet.
  require("images.anchor").draw(win, "full", target, {
    defer = true,
    on_done = function(ok, err)
      if not ok then notify().error(err or "Anzeige fehlgeschlagen") end
    end,
  })

  return true
end

return M
