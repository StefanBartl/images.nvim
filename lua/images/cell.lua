---@module 'images.cell'
---@brief Pixel-Seitenverhältnis einer Terminalzelle — erfragt statt geraten.
---@description
--- `images.scale.CELL_ASPECT` nimmt an, eine Zelle sei doppelt so hoch wie
--- breit (0.5). Das ist für gängige Monospace-Schriften ungefähr richtig und
--- für `images.redact` gut genug, aber es ist eben eine Annahme: liegt die
--- echte Zelle bei 0.46, berechnet `images.scale.fit_cells` eine Box, die
--- ein bis zwei Zeilen höher ist als das Bild darin je füllen kann. Das
--- Terminal skaliert mit `preserveAspectRatio=1` auf "contain", der Rest
--- bleibt sichtbar leer — bei einem Hover-Float, dessen Rahmen genau diese
--- Box ist, fällt der leere Streifen unter dem Bild sofort auf.
---
--- Deshalb hier eine echte Messung: `CSI 16 t` fragt die Zellgröße in Pixeln
--- ab, das Terminal antwortet mit `CSI 6 ; <höhe> ; <breite> t`, und Neovim
--- reicht die Antwort als `TermResponse` durch.
---
--- **Warum das die Leitplanke "keine Zellmessung" (docs/ROADMAP/README.md)
--- nicht umstößt:** die Messung ist nirgends Voraussetzung. Antwortet das
--- Terminal nicht — tmux ohne Passthrough, SSH, ein Terminal ohne
--- Fensterabfragen —, bleibt es bei der Annahme, und alles funktioniert wie
--- vorher, nur mit dem bekannten Rand. Wer den Wert kennt, trägt ihn unter
--- `display.cell_aspect` ein und übergeht die Abfrage ganz. Gemessen wird
--- einmal pro Sitzung, asynchron, ohne dass irgendein Zeichenpfad darauf
--- wartet.
---
--- Das Ergebnis wird nach `images.scale.CELL_ASPECT` geschrieben statt an
--- jeden Aufrufer durchgereicht: `fit_cells` hat vier Aufrufer (`ascii`,
--- `redact`, `zen` und markdown.nvims Hover-Canvas), und eine zusätzliche
--- Signaturposition, die alle vier mitschleppen müssten, wäre in jedem
--- einzelnen derselbe Wert. `images.scale` bleibt so auch die reine,
--- terminalfreie Rechenstelle, die es laut eigener Moduldoku sein soll.

local M = {}

local ESC = "\27"

--- Grenzen, innerhalb derer eine Antwort plausibel ist. Eine Zelle ist
--- schmaler als hoch, aber nie extrem: 0.2 wäre eine absurd schmale, 1.5 eine
--- breitere-als-hohe Zelle. Alles außerhalb ist eher eine fremde Antwort, die
--- zufällig auf das Muster passt, als eine echte Zellgröße — und eine falsche
--- Messung wäre schlechter als die Annahme, die sie ersetzen soll.
M.MIN_ASPECT, M.MAX_ASPECT = 0.2, 1.5

--- Wie lange auf die Antwort gehört wird. Ein Terminal, das `CSI 16 t` kennt,
--- antwortet sofort; danach hört der Handler nur noch fremde Sequenzen mit
--- und wird abgeräumt.
M.TIMEOUT_MS = 1000

--- Gemessenes Verhältnis, oder nil, solange nichts (Brauchbares) kam.
---@type number|nil
local measured = nil

--- Ob in dieser Sitzung schon gefragt wurde.
---@type boolean
local asked = false

--- `images.scale.CELL_ASPECT` in seinem ursprünglichen Zustand, einmal
--- gesichert: `M.apply` überschreibt das Feld, und ohne diese Kopie wäre der
--- Rückfallwert nach dem ersten `apply` der eigene vorherige Output statt der
--- dokumentierten Annahme.
---@type number|nil
local assumed = nil

---@return number
local function assumption()
  if not assumed then assumed = require("images.scale").CELL_ASPECT end
  return assumed
end

--- Das gemessene Verhältnis, oder nil, wenn nichts Brauchbares ankam.
---@return number|nil
function M.measured()
  return measured
end

--- Messung und Frage-Zustand verwerfen. Für Tests und für den Fall, dass die
--- Konfiguration nach dem ersten Anlauf geändert wurde.
---@return nil
function M.reset()
  measured, asked = nil, false
end

--- Eine Terminalantwort auf `CSI 16 t` auswerten.
---
--- Reine Funktion, damit das Format ohne Terminal prüfbar bleibt — der
--- Roundtrip selbst ist es nicht. Gesucht wird `CSI 6 ; <höhe> ; <breite> t`
--- irgendwo in der Sequenz statt als exakte Gesamtübereinstimmung: es kommen
--- auch fremde Antworten durch denselben Kanal, und manche Terminals hängen
--- Füllzeichen an.
---@param seq string|nil Rohe Sequenz aus `TermResponse`
---@return number|nil aspect Breite/Höhe einer Zelle, oder nil bei allem anderen
function M.parse(seq)
  if type(seq) ~= "string" then return nil end

  local h, w = seq:match(ESC .. "%[6;(%d+);(%d+)t")
  if not (h and w) then return nil end

  h, w = tonumber(h), tonumber(w)
  if not (h and w) or h <= 0 or w <= 0 then return nil end

  local aspect = w / h
  if aspect < M.MIN_ASPECT or aspect > M.MAX_ASPECT then return nil end
  return aspect
end

--- Das wirksame Verhältnis: Konfiguration schlägt Messung schlägt Annahme.
---
--- Ein konfigurierter Wert gewinnt auch gegen eine erfolgreiche Messung —
--- wer ihn setzt, weiß etwas, das die Abfrage nicht weiß (eine Schrift mit
--- ungewöhnlicher Zeilenhöhe, ein Terminal, das plausibel aber falsch
--- antwortet).
---@return number
function M.aspect()
  local ok, config = pcall(require, "images.config")
  if ok then
    local configured = (config.get().display or {}).cell_aspect
    if type(configured) == "number" and configured > 0 then return configured end
  end
  return measured or assumption()
end

--- Das wirksame Verhältnis in `images.scale.CELL_ASPECT` schreiben, wo alle
--- vier Aufrufer von `fit_cells` es ohnehin schon lesen.
---@return number applied
function M.apply()
  local aspect = M.aspect()
  require("images.scale").CELL_ASPECT = aspect
  return aspect
end

--- Einmal pro Sitzung beim Terminal nachfragen.
---
--- Die Antwort kommt asynchron; bis dahin gilt weiter, was `M.aspect` ohne
--- sie liefert. Kein Aufrufer wartet darauf, deshalb gibt es hier auch keinen
--- Callback — wer den Wert braucht, liest ihn beim nächsten Zeichnen.
---@return boolean asked Ob die Frage tatsächlich rausging
function M.query()
  if asked then return false end
  if type(vim.api.nvim_ui_send) ~= "function" then return false end

  -- Ohne angehängte UI gibt es niemanden, der antworten könnte. Bewusst nicht
  -- als "gefragt" verbucht: bei `nvim --embed`/`--listen` hängt sich die UI
  -- erst später an, und dann ist die Frage wieder sinnvoll.
  if #vim.api.nvim_list_uis() == 0 then
    vim.api.nvim_create_autocmd("UIEnter", {
      once = true,
      desc = "images.nvim: Zellgröße erfragen, sobald eine UI da ist",
      callback = function()
        M.query()
      end,
    })
    return false
  end

  asked = true

  local id = vim.api.nvim_create_autocmd("TermResponse", {
    desc = "images.nvim: Zellgröße aus der Terminalantwort lesen",
    callback = function(ev)
      -- Neovim hat die Nutzlast über die Versionen mal als String, mal als
      -- Tabelle mit `sequence` geliefert; beides kostet hier eine Zeile.
      local data = ev and ev.data
      local seq = type(data) == "table" and data.sequence or data

      local aspect = M.parse(seq)
      if not aspect then return end -- fremde Antwort: weiterhören

      measured = aspect
      M.apply()
      return true -- passt: diesen Handler abmelden
    end,
  })

  vim.api.nvim_ui_send(ESC .. "[16t")

  -- Antwortet niemand, bliebe der Handler sonst die ganze Sitzung lang an
  -- jeder fremden Terminalantwort hängen.
  vim.defer_fn(function()
    pcall(vim.api.nvim_del_autocmd, id)
  end, M.TIMEOUT_MS)

  return true
end

return M
