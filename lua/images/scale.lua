---@module 'images.scale'
---@brief Reine Berechnung: wie groß zwei Bilder relativ zueinander wirken sollen.
---@description
--- Ohne das würde `:Image compare` jedes Bild unabhängig auf seine Pane
--- strecken — ein 200x100-Icon neben einem 4000x2000-Foto sähen dann gleich
--- groß aus, genau das Problem, das FEATURES.md an der Galerie beschreibt
--- ("wegnormiert"). Mit echten Pixelmaßen (via `images.info`, wenn
--- ImageMagick installiert ist) bekommt das kleinere Bild stattdessen eine
--- proportional kleinere Box, statt seine Pane zu füllen.
---
--- Reine Funktion, kein Terminal- oder Dateisystemzugriff — daher ohne
--- Terminal testbar, wie `images.gallery`.

local M = {}

--- Wie stark ein Bild relativ zum größeren geschrumpft wird, bevor es
--- unlesbar würde. 0.35 heißt: auch ein winziges Icon neben einem riesigen
--- Foto zeigt noch mindestens 35% der Pane — genug, um "kleiner" zu
--- vermitteln, ohne zu verschwinden.
M.MIN_SCALE = 0.35

---@class Images.Scale.Dims
---@field width integer Pixel
---@field height integer Pixel

---@class Images.Scale.Result
---@field a number Faktor für Bild A, 0 < a <= 1
---@field b number Faktor für Bild B, 0 < b <= 1

--- Skalenfaktoren für zwei Bilder berechnen. Verglichen wird über die
--- Bilddiagonale (`sqrt(w²+h²)`) als ein einzelner Größenwert — bei
--- unterschiedlichen Seitenverhältnissen gibt es keine eindeutig "richtige"
--- Metrik, aber die Diagonale ist eine gängige, nachvollziehbare Wahl.
---
--- Ohne beide Maße (z.B. weil ImageMagick fehlt) bekommen beide 1.0 — exakt
--- das bisherige Verhalten, jedes Bild füllt seine Pane. Laut Leitplanke in
--- docs/ROADMAP/README.md verbessert ImageMagick Features, ermöglicht sie
--- aber nicht.
---@param a Images.Scale.Dims|nil
---@param b Images.Scale.Dims|nil
---@return Images.Scale.Result
function M.compute(a, b)
  if not (a and b and a.width > 0 and a.height > 0 and b.width > 0 and b.height > 0) then return { a = 1, b = 1 } end

  local diag_a = math.sqrt(a.width ^ 2 + a.height ^ 2)
  local diag_b = math.sqrt(b.width ^ 2 + b.height ^ 2)

  if diag_a == diag_b then return { a = 1, b = 1 } end

  local ratio = math.max(M.MIN_SCALE, math.min(diag_a, diag_b) / math.max(diag_a, diag_b))
  if diag_a > diag_b then return { a = 1, b = ratio } end
  return { a = ratio, b = 1 }
end

--- Zellenbox innerhalb eines Fensters bestimmen: `factor` der vollen Größe,
--- zentriert statt in einer Ecke klebend.
---@param win_width integer Zellen
---@param win_height integer Zellen
---@param factor number 0 < factor <= 1
---@return integer cols, integer rows, integer col_offset, integer row_offset
function M.box(win_width, win_height, factor)
  local cols = math.max(1, math.floor(win_width * factor))
  local rows = math.max(1, math.floor(win_height * factor))
  local col_offset = math.floor((win_width - cols) / 2)
  local row_offset = math.floor((win_height - rows) / 2)
  return cols, rows, col_offset, row_offset
end

return M
