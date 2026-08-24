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
--- Fünf Eigenheiten, die beim Bauen Zeit gekostet haben:
---
--- * Geschrieben wird über `vim.api.nvim_ui_send`, nicht über `io.stdout:write`.
---   Letzteres zeichnet nur beim ersten Mal pro Terminal-Session.
--- * Ohne Cursor-Positionierung landet das Bild am unteren Rand und schiebt die
---   Statusline hoch. Daher `ESC[s` / `ESC[<row>;<col>H` / Payload / `ESC[u`.
--- * Diese Teile müssen in **einem** `nvim_ui_send` rausgehen, siehe
---   `sequence_for`. Neovims eigener TUI-Renderer schreibt in denselben
---   tty-Strom; zwischen zwei Aufrufen kann er flushen und dabei eigene
---   Cursorbewegungen einschieben. Passiert das zwischen Positionierung und
---   Payload, zeichnet das Terminal das Bild dort, wo Neovims Cursor gerade
---   steht — dasselbe Ergebnis wie ganz ohne Positionierung, nur sporadisch
---   statt immer und damit deutlich schwerer zuzuordnen.
--- * Ein Bild, das über die letzte Zeile hinausragt, scrollt den ganzen Schirm
---   — Neovims Grid inklusive. `ESC[u` stellt danach die Cursorposition wieder
---   her, den Scroll aber nicht: die Statusline bleibt hochgerutscht, bis
---   `M.clear` per `:mode` alles neu malt. Dagegen `clamp_to_screen`.
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
  if capability then return capability end

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

--- Dateiinhalt lesen. SVG wird zuerst nach PNG konvertiert (siehe
--- `images.convert`) — OSC 1337 erwartet Rasterbytes, WezTerm kann SVG selbst
--- nicht dekodieren. Für jedes andere Format ist das ein reiner Durchreicher.
---@param file string
---@return string|nil data
---@return string|nil err
local function read_file(file)
  if type(file) ~= "string" or file == "" then return nil, "Kein Dateipfad angegeben" end

  local effective = file
  if require("images.convert").is_svg(file) then
    local png, conv_err = require("images.convert").to_png(file)
    if not png then return nil, conv_err end
    effective = png
  end

  local raw, read_err = require("lib.nvim.fs.read")(effective)
  if not raw then return nil, ("Datei nicht lesbar: %s (%s)"):format(effective, read_err or "?") end
  if raw == "" then return nil, "Datei ist leer: " .. effective end
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

--- Zeichenbox so beschneiden, dass sie auf den Schirm passt.
---
--- Vertikal bleibt eine Zeile frei, und das ist kein Sicherheitsabstand aus
--- Vorsicht: OSC 1337 mit `inline=1` rückt den Cursor nach dem Bild um dessen
--- Höhe nach unten. Endet das Bild auf der letzten Zeile, löst genau dieser
--- eine Schritt den Scroll aus, den die Box selbst gerade noch vermieden
--- hätte — und ein Scroll verschiebt Neovims ganzes Grid, ohne dass Neovim
--- davon erfährt (siehe Moduldoku).
---@param row integer 1-basierte Terminalzeile
---@param col integer 1-basierte Terminalspalte
---@param cols integer gewünschte Breite in Zellen
---@param rows integer gewünschte Höhe in Zellen
---@return integer cols
---@return integer rows
local function clamp_to_screen(row, col, cols, rows)
  return math.max(1, math.min(cols, vim.o.columns - col + 1)), math.max(1, math.min(rows, vim.o.lines - row))
end

--- Die vollständige Sequenz für ein Bild an einer Position — als **ein**
--- String, der in einem Stück rausgeht. Warum das zusammenbleiben muss, steht
--- in der Moduldoku; hier nur der Zusatz `ESC[?7l`/`ESC[?7h`: Autowrap aus,
--- damit ein Pixel Überbreite keinen Zeilenumbruch erzwingt, der seinerseits
--- am unteren Rand scrollen würde.
---@param raw string Rohe Dateibytes
---@param row integer 1-basierte Terminalzeile
---@param col integer 1-basierte Terminalspalte
---@param cols integer Breite in Zellen
---@param rows integer Höhe in Zellen
---@return string
local function sequence_for(raw, row, col, cols, rows)
  return table.concat({
    ESC .. "[s", -- Cursor sichern
    ESC .. "[?7l", -- Autowrap aus
    ("%s[%d;%dH"):format(ESC, row, col), -- positionieren
    payload_for(raw, cols, rows),
    ESC .. "[?7h", -- Autowrap zurück
    ESC .. "[u", -- Cursor zurück
  })
end

--- Anstehende Bildschirmausgabe erzwingen, BEVOR gezeichnet wird.
---
--- Sechste Eigenheit, die Zeit gekostet hat: `nvim_ui_send` schreibt sofort
--- ans Terminal, Neovims eigener Repaint läuft dagegen erst, wenn die
--- Steuerung in die Hauptschleife zurückkehrt. Wer also ein Fenster öffnet
--- und im selben Tick hineinzeichnet, sendet das Bild und lässt Neovim
--- danach die (leeren) Zellen dieses Fensters darüber malen — Popup da,
--- Bild weg. Genau so verhielt sich `:Image zen`.
---
--- Deshalb hier und nicht beim Aufrufer: Es ist eine Invariante des
--- Zeichenpfads, nicht der Fensterlogik. Wo der Schirm ohnehin steht
--- (`images.browse`s Picker-Preview, `images.gallery` über bestehendem
--- Text), ist es ein wirkungsloses Flush.
---@return nil
local function flush_pending_redraw()
  pcall(vim.cmd, "redraw")
end

--- Ein Bild an einer Terminalposition zeichnen.
---
--- `cols`/`rows` sind ein Wunsch, keine Zusage: was von `row`/`col` aus nicht
--- mehr auf den Schirm passt, wird vorher weggeschnitten (`clamp_to_screen`).
--- Ein zu großer Wert kostet also Bildgröße, nicht die Bildschirmordnung.
---@param file string Absoluter Pfad zu einer Bilddatei
---@param row integer 1-basierte Terminalzeile
---@param col integer 1-basierte Terminalspalte
---@param cols integer Gewünschte Breite in Zellen, auf den Schirm beschnitten
---@param rows integer Gewünschte Höhe in Zellen, auf den Schirm beschnitten
---@return boolean ok
---@return string|nil err
function M.draw(file, row, col, cols, rows)
  if not M.available() then return false, "Terminalausgabe nicht verfügbar (nvim_ui_send fehlt, benötigt API-Level 14)" end

  -- Vor dem Lesen: schlägt das Lesen fehl, war der Flush umsonst, aber
  -- harmlos — umgekehrt käme er zu spät.
  local raw, err = read_file(file)
  if not raw then return false, err end

  -- `display.terminal_padding` darf negativ sein (siehe `images.anchor`), und
  -- nahe am oberen/linken Rand kann das rechnerisch unter 1 fallen. `CSI 0;0H`
  -- ist zwar in der Praxis wie `CSI 1;1H`, aber darauf soll sich hier nichts
  -- verlassen — und `clamp_to_screen` würde aus einem zu kleinen `row` eine zu
  -- große Höhe ableiten.
  row = math.max(1, row)
  col = math.max(1, col)

  cols, rows = clamp_to_screen(row, col, cols, rows)

  flush_pending_redraw()

  vim.api.nvim_ui_send(sequence_for(raw, row, col, cols, rows))

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
---
--- Jede Kachel geht als eigene, in sich vollständige Sequenz raus (Cursor
--- sichern, positionieren, zeichnen, zurück) statt einmal für den ganzen
--- Block. Das kostet pro Kachel ein paar Bytes mehr, ist aber der Punkt der
--- Übung: nur so klebt jede Positionierung untrennbar an ihrer Payload. Alles
--- zu einem einzigen String zu verketten wäre noch strenger, hielte dann aber
--- sämtliche Base64-Anteile einer Galerie gleichzeitig im Speicher.
---@param placements Images.Placement[]
---@return integer drawn Anzahl tatsächlich gezeichneter Bilder
---@return string[] errors Fehlermeldungen der übersprungenen Bilder
function M.draw_many(placements)
  if not M.available() then return 0, { "Terminalausgabe nicht verfügbar (nvim_ui_send fehlt)" } end

  local send = vim.api.nvim_ui_send
  local drawn, errors = 0, {}

  flush_pending_redraw()

  for _, p in ipairs(placements) do
    local raw, err = read_file(p.file)
    if raw then
      local cols, rows = clamp_to_screen(p.row, p.col, p.cols, p.rows)
      send(sequence_for(raw, p.row, p.col, cols, rows))
      drawn = drawn + 1
    else
      errors[#errors + 1] = err or ("Übersprungen: " .. tostring(p.file))
    end
  end

  if drawn > 0 then showing = true end
  return drawn, errors
end

--- Alle angezeigten Bilder entfernen. `:mode` erzwingt einen vollständigen
--- Repaint, der die belegten Zellen überschreibt, ohne den Schirm zu leeren.
---@return nil
function M.clear()
  if not showing then return end
  showing = false
  pcall(vim.cmd, "mode")
end

return M
