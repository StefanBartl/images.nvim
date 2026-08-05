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
---
--- Das Protokoll kennt keine Bild-IDs: Gezeichnetes lässt sich nicht einzeln
--- entfernen, nur der ganze Schirm neu zeichnen. Deshalb hält dieses Modul
--- lediglich ein Flag statt einer Platzierungs-Verwaltung.

local M = {}

local ESC, BEL = "\27", "\7"

--- Ob gerade mindestens ein Bild auf dem Schirm steht.
---@type boolean
local showing = false

---@return boolean
function M.is_showing()
  return showing
end

--- Ob die Terminalausgabe zur Verfügung steht.
--- `nvim_ui_send` gibt es erst ab API-Level 14.
---@return boolean
function M.available()
  return type(vim.api.nvim_ui_send) == "function"
end

---@class Images.Capability
---@field ok boolean Ob gezeichnet werden kann
---@field terminal string|nil Erkannter Terminalname
---@field reason string|nil Grund, wenn `ok` false ist
---@field hint string|nil Konkreter nächster Schritt für den User

--- Ergebnis der Fähigkeitsprüfung, einmal pro Sitzung ermittelt.
---@type Images.Capability|nil
local capability = nil

--- Terminals, die das iTerm2-Protokoll umsetzen, mit der Umgebungsvariable,
--- an der sie erkennbar sind. Bewusst kurz: OSC 1337 kennt keine
--- Fähigkeitsabfrage, deshalb bleibt nur eine Namensliste.
---@type { name: string, detect: fun(): boolean }[]
local KNOWN = {
  {
    name = "WezTerm",
    detect = function()
      return (vim.env.WEZTERM_EXECUTABLE or vim.env.WEZTERM_VERSION or vim.env.WEZTERM_PANE) ~= nil
    end,
  },
  {
    name = "iTerm2",
    detect = function()
      local tp = (vim.env.TERM_PROGRAM or ""):lower()
      return tp:find("iterm", 1, true) ~= nil or (vim.env.LC_TERMINAL or ""):lower():find("iterm", 1, true) ~= nil
    end,
  },
  {
    name = "Konsole",
    detect = function()
      return vim.env.KONSOLE_VERSION ~= nil
    end,
  },
}

--- Prüfen, ob dieses Terminal Bilder darstellen kann.
---
--- Bewusst *keine* harte Sperre: die Erkennung ist eine Heuristik über
--- Umgebungsvariablen, weil OSC 1337 keine Abfrage kennt. Ein Fehlalarm würde
--- sonst ein funktionierendes Setup abwürgen. Der Aufrufer entscheidet, was
--- mit `ok = false` geschieht — hier wird nur berichtet.
---
--- Das Ergebnis wird gemerkt: die Umgebung ändert sich innerhalb einer Sitzung
--- nicht, und der Aufruf sitzt vor jedem Zeichnen.
---@param force boolean|nil Erkennung übergehen und Unterstützung annehmen
---@return Images.Capability
function M.capability(force)
  if capability then
    return capability
  end

  if not M.available() then
    capability = {
      ok = false,
      reason = "`nvim_ui_send` fehlt (benötigt API-Level 14)",
      hint = "Neovim aktualisieren — ohne diese API kann kein Bild gezeichnet werden",
    }
    return capability
  end

  local detected
  for _, term in ipairs(KNOWN) do
    local ok_detect, hit = pcall(term.detect)
    if ok_detect and hit then
      detected = term.name
      break
    end
  end

  if detected then
    capability = { ok = true, terminal = detected }
  elseif force then
    capability = { ok = true, terminal = nil }
  else
    capability = {
      ok = false,
      reason = "Terminal nicht erkannt (TERM_PROGRAM=" .. (vim.env.TERM_PROGRAM or "leer") .. ")",
      hint = "Test: `wezterm imgcat bild.png` bzw. das Äquivalent. "
        .. "Funktioniert es, `display.assume_supported = true` setzen.",
    }
  end

  -- tmux reicht die Sequenzen nur mit allow-passthrough durch. Das gilt auch
  -- für ein erkanntes Terminal, deshalb hier und nicht im else-Zweig.
  if vim.env.TMUX and vim.env.TMUX ~= "" and capability.ok then
    capability.hint = "In tmux: `set -g allow-passthrough on` nötig, sonst kommt nichts an"
  end

  return capability
end

--- Gemerktes Prüfergebnis verwerfen. Für Tests und für den Fall, dass die
--- Konfiguration nach der ersten Prüfung geändert wurde.
---@return nil
function M.reset_capability()
  capability = nil
end

--- Dateiinhalt lesen.
---@param file string
---@return string|nil data
---@return string|nil err
local function read_file(file)
  if type(file) ~= "string" or file == "" then
    return nil, "Kein Dateipfad angegeben"
  end
  local fd, open_err = io.open(file, "rb")
  if not fd then
    return nil, ("Datei nicht lesbar: %s (%s)"):format(file, open_err or "?")
  end
  local raw = fd:read("*a")
  fd:close()
  if not raw or raw == "" then
    return nil, "Datei ist leer: " .. file
  end
  return raw
end

--- OSC-1337-Sequenz für einen Bilddateiinhalt bauen.
---@param raw string Rohe Dateibytes
---@param cols integer Breite in Zellen
---@param rows integer Höhe in Zellen
---@return string
local function payload_for(raw, cols, rows)
  -- table.concat statt wiederholter `..`-Verkettung: der Base64-Anteil ist
  -- bei großen Bildern mehrere hundert KB groß, jede Zwischenkopie zählt.
  return table.concat({
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
  if not M.available() then
    return false, "Terminalausgabe nicht verfügbar (nvim_ui_send fehlt, benötigt API-Level 14)"
  end

  local raw, err = read_file(file)
  if not raw then
    return false, err
  end

  local send = vim.api.nvim_ui_send
  send(ESC .. "[s")
  send(ESC .. "[" .. row .. ";" .. col .. "H")
  send(payload_for(raw, cols, rows))
  send(ESC .. "[u")

  showing = true
  return true
end

---@class Images.Placement
---@field file string Absoluter Pfad
---@field row integer 1-basierte Terminalzeile
---@field col integer 1-basierte Terminalspalte
---@field cols integer Breite in Zellen
---@field rows integer Höhe in Zellen

--- Mehrere Bilder in einem Rutsch zeichnen.
--- Der Cursor wird einmal für den ganzen Block gesichert statt pro Bild — bei
--- einer Galerie mit vielen Kacheln spart das die Hälfte der Sequenzen.
---@param placements Images.Placement[]
---@return integer drawn Anzahl tatsächlich gezeichneter Bilder
---@return string[] errors Fehlermeldungen der übersprungenen Bilder
function M.draw_many(placements)
  if not M.available() then
    return 0, { "Terminalausgabe nicht verfügbar (nvim_ui_send fehlt)" }
  end

  local send = vim.api.nvim_ui_send
  local drawn, errors = 0, {}

  send(ESC .. "[s")
  for _, p in ipairs(placements) do
    local raw, err = read_file(p.file)
    if raw then
      send(ESC .. "[" .. p.row .. ";" .. p.col .. "H")
      send(payload_for(raw, p.cols, p.rows))
      drawn = drawn + 1
    else
      errors[#errors + 1] = err or ("Übersprungen: " .. tostring(p.file))
    end
  end
  send(ESC .. "[u")

  if drawn > 0 then
    showing = true
  end
  return drawn, errors
end

--- Alle angezeigten Bilder entfernen. `:mode` erzwingt einen vollständigen
--- Repaint, der die belegten Zellen überschreibt, ohne den Schirm zu leeren.
---@return nil
function M.clear()
  if not showing then
    return
  end
  showing = false
  pcall(vim.cmd, "mode")
end

return M
