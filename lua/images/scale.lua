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

--- Angenommenes Pixel-Seitenverhältnis einer Terminalzelle (Breite/Höhe).
--- images.nvim fragt das Terminal dafür nie ab (siehe die "keine
--- Zellmessung"-Leitplanke in docs/ROADMAP/README.md) — 0.5 ist eine grobe,
--- für gängige Monospace-Schriften typische Annahme (eine Zelle ist ungefähr
--- doppelt so hoch wie breit). Für `images.redact` reicht das: `M.fit_cells`
--- wählt die Zeichenbox so, dass `preserveAspectRatio=1` kaum noch etwas zu
--- letterboxen hat, und `M.cell_box_to_pixels`s Sicherheitsmarge fängt den
--- Rest ab — lieber eine Zelle zu viel geschwärzt als eine zu wenig.
M.CELL_ASPECT = 0.5

--- Zeichenbox in Zellen bestimmen, die `image_px`s Seitenverhältnis (über
--- `M.CELL_ASPECT` in Zellen ausgedrückt) innerhalb der Maximalgröße
--- ausfüllt — dieselbe "an die längere Achse anpassen"-Idee wie bei jedem
--- Seitenverhältnis-Fit, nur mit dem Zwischenschritt Pixel→Zelle.
---@param max_cols integer
---@param max_rows integer
---@param image_px Images.Scale.Dims|nil
---@return integer cols, integer rows
function M.fit_cells(max_cols, max_rows, image_px)
  if not (image_px and image_px.width > 0 and image_px.height > 0) then return max_cols, max_rows end

  local image_aspect = image_px.width / image_px.height
  local cols = math.floor(max_rows * image_aspect / M.CELL_ASPECT)
  if cols <= max_cols then return math.max(1, cols), max_rows end

  local rows = math.floor(max_cols * M.CELL_ASPECT / image_aspect)
  return max_cols, math.max(1, rows)
end

--- Eine 1-basierte, einschließende Zellbox (relativ zur Zeichenbox) in eine
--- Pixelbox der Quelldatei umrechnen. Setzt voraus, dass `draw_cols`/
--- `draw_rows` bereits über `M.fit_cells` gewählt wurden — sonst würde die
--- angenommene 1:1-Entsprechung zwischen Zellgitter und sichtbarem Bild
--- spürbar danebenliegen. `padding_cells` wächst die Box vor der Umrechnung
--- nach außen: eine Redaktion soll lieber zu groß als zu klein ausfallen.
---@param box { row1: integer, col1: integer, row2: integer, col2: integer }
---@param draw_cols integer
---@param draw_rows integer
---@param image_px Images.Scale.Dims
---@param padding_cells integer|nil
---@return { x1: integer, y1: integer, x2: integer, y2: integer }
function M.cell_box_to_pixels(box, draw_cols, draw_rows, image_px, padding_cells)
  padding_cells = padding_cells or 0

  local col1 = math.max(1, box.col1 - padding_cells)
  local row1 = math.max(1, box.row1 - padding_cells)
  local col2 = math.min(draw_cols, box.col2 + padding_cells)
  local row2 = math.min(draw_rows, box.row2 + padding_cells)

  local scale_x = image_px.width / draw_cols
  local scale_y = image_px.height / draw_rows

  local x1 = math.floor((col1 - 1) * scale_x)
  local y1 = math.floor((row1 - 1) * scale_y)
  local x2 = math.ceil(col2 * scale_x)
  local y2 = math.ceil(row2 * scale_y)

  return {
    x1 = math.max(0, math.min(x1, image_px.width)),
    y1 = math.max(0, math.min(y1, image_px.height)),
    x2 = math.max(0, math.min(x2, image_px.width)),
    y2 = math.max(0, math.min(y2, image_px.height)),
  }
end

return M
