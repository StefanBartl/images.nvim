---@module 'images.terminal'
---@brief Bildausgabe im Terminal über das iTerm2-Protokoll (OSC 1337).
---@description
--- Warum OSC 1337 und nicht das Kitty-Graphics-Protokoll:
---
--- Auf nativem Windows-Neovim in WezTerm zeichnet das Terminal aus Neovim heraus
--- ausschließlich OSC 1337. Kitty-APC (`ESC _G`) kommt nie an — in rohem pwsh
--- funktionieren beide Protokolle, der Unterschied entsteht erst durch Neovims
--- Ausgabeschicht. Da `snacks.image` und `image.nvim` beide nur Kitty-APC senden,
--- sind sie dort prinzipiell unbrauchbar, unabhängig von jeder Konfiguration.
---
--- Drei Eigenheiten, die beim Bauen Zeit gekostet haben:
---
--- * Geschrieben wird über `vim.api.nvim_ui_send`, nicht über `io.stdout:write`.
---   Letzteres zeichnet nur beim ersten Mal pro Terminal-Session.
--- * Ohne Cursor-Positionierung landet das Bild am unteren Rand und schiebt die
---   Statusline hoch. Daher `ESC[s` / `ESC[<row>;<col>H` / Payload / `ESC[u`.
--- * `width`/`height` werden in **Zellen** angegeben, nicht in Pixeln. Zusammen
---   mit `preserveAspectRatio=1` skaliert das Terminal selbst, und die Zellgröße
---   in Pixeln muss nirgends bekannt sein.

local M = {}

local ESC, BEL = "\27", "\7"

--- Ob gerade ein Bild auf dem Schirm steht.
---@type boolean
local showing = false

---@return boolean
function M.is_showing()
  return showing
end

--- Ein Bild an einer Terminalposition zeichnen.
---@param file string Absoluter Pfad zu einer Bilddatei
---@param row integer 1-basierte Terminalzeile
---@param col integer 1-basierte Terminalspalte
---@param cols integer Maximale Breite in Zellen
---@param rows integer Maximale Höhe in Zellen
---@return boolean ok
---@return string|nil err
function M.draw(file, row, col, cols, rows)
  local fd, open_err = io.open(file, "rb")
  if not fd then
    return false, ("Datei nicht lesbar: %s (%s)"):format(file, open_err or "?")
  end
  local raw = fd:read("*a")
  fd:close()

  if not raw or raw == "" then
    return false, "Datei ist leer: " .. file
  end

  local payload = table.concat({
    ESC,
    "]1337;File=inline=1",
    ";size=" .. #raw,
    ";width=" .. cols,
    ";height=" .. rows,
    ";preserveAspectRatio=1",
    ":",
    vim.base64.encode(raw),
    BEL,
  })

  local send = vim.api.nvim_ui_send
  send(ESC .. "[s")
  send(ESC .. "[" .. row .. ";" .. col .. "H")
  send(payload)
  send(ESC .. "[u")

  showing = true
  return true
end

--- Bild entfernen. `:mode` erzwingt einen vollständigen Repaint, der die vom
--- Bild belegten Zellen überschreibt, ohne den Bildschirm zu leeren.
---@return nil
function M.clear()
  if not showing then
    return
  end
  showing = false
  vim.cmd("mode")
end

--- Ob die Terminalausgabe überhaupt zur Verfügung steht.
--- `nvim_ui_send` gibt es erst ab API-Level 14.
---@return boolean
function M.available()
  return vim.api.nvim_ui_send ~= nil
end

return M
