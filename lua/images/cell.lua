---@module 'images.cell'
---@brief Pixel-Seitenverhältnis einer Terminalzelle.
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
--- **Warum das hier konfiguriert und nicht gemessen wird.** Die naheliegende
--- Abfrage ist `CSI 16 t`; das Terminal antwortet mit
--- `CSI 6 ; <höhe> ; <breite> t`. Aus einem Neovim-Plugin heraus ist diese
--- Antwort nicht erreichbar: `TermResponse` feuert laut `:h TermResponse`
--- ausschließlich für **DA1-, OSC-, DCS- und APC**-Antworten, und
--- `CSI 6 ; … t` ist eine schlichte CSI-Antwort. Sie wird nie durchgereicht,
--- unabhängig vom Terminal. `nvim_list_uis()` kennt nur Zellmaße
--- (`width`/`height` in Zellen), keine Pixel. Damit gibt es aus Neovim heraus
--- keinen Weg zur echten Zellgröße — ein früherer Anlauf über `CSI 16 t` +
--- `TermResponse` stand hier und hat aus genau diesem Grund nie funktioniert.
--- Details und Messprotokoll: `docs/ROADMAP/TERMINALS.md`.
---
--- Deshalb: `display.cell_aspect` setzen, wer es genau haben will; sonst
--- bleibt es bei der Annahme. Das ist kein Rückschritt gegenüber vorher — die
--- Annahme war schon immer der tatsächlich wirksame Wert.
---
--- Der Wert wird nach `images.scale.CELL_ASPECT` geschrieben statt an jeden
--- Aufrufer durchgereicht: `fit_cells` hat vier Aufrufer (`ascii`, `redact`,
--- `zen` und markdown.nvims Hover-Canvas), und eine zusätzliche
--- Signaturposition, die alle vier mitschleppen müssten, wäre in jedem
--- einzelnen derselbe Wert. `images.scale` bleibt so auch die reine,
--- terminalfreie Rechenstelle, die es laut eigener Moduldoku sein soll.

local M = {}

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

--- Das wirksame Verhältnis: Konfiguration schlägt Annahme.
---@return number
function M.aspect()
  local ok, config = pcall(require, "images.config")
  if ok then
    local configured = (config.get().display or {}).cell_aspect
    if type(configured) == "number" and configured > 0 then return configured end
  end
  return assumption()
end

--- Das wirksame Verhältnis in `images.scale.CELL_ASPECT` schreiben, wo alle
--- vier Aufrufer von `fit_cells` es ohnehin schon lesen.
---@return number applied
function M.apply()
  local aspect = M.aspect()
  require("images.scale").CELL_ASPECT = aspect
  return aspect
end

return M
