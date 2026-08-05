---@module 'images.gallery'
---@brief Mehrere Bilder gleichzeitig nebeneinander anzeigen.
---@description
--- Rein rechnerisches Modul: es verteilt N Bilder auf ein Raster und liefert
--- Platzierungen für `images.terminal.draw_many`. Kein Fenster, kein State,
--- keine Seiteneffekte — dadurch ist die Aufteilung ohne Terminal testbar.

local M = {}

---@class Images.Gallery.Opts
---@field columns integer|nil Spaltenzahl; nil = automatisch aus der Anzahl
---@field gap integer Zellen Abstand zwischen den Kacheln
---@field top integer 1-basierte Startzeile
---@field left integer 1-basierte Startspalte
---@field width integer Verfügbare Breite in Zellen
---@field height integer Verfügbare Höhe in Zellen

--- Spaltenzahl schätzen, wenn keine vorgegeben ist.
--- Ziel ist ein möglichst quadratisches Raster, gedeckelt auf 4 Spalten —
--- darüber werden die Kacheln in einem üblichen Terminal zu schmal, um noch
--- etwas zu erkennen.
---@param count integer
---@return integer
local function auto_columns(count)
  if count <= 1 then
    return 1
  end
  local cols = math.ceil(math.sqrt(count))
  return math.max(1, math.min(cols, 4))
end

--- Bilder auf ein Raster verteilen.
---@param files string[] Absolute Pfade
---@param opts Images.Gallery.Opts
---@return Images.Placement[] placements
---@return integer skipped Anzahl Bilder, für die kein Platz mehr war
function M.layout(files, opts)
  local placements = {}
  local count = #files
  if count == 0 then
    return placements, 0
  end

  local columns = opts.columns or auto_columns(count)
  columns = math.max(1, math.min(columns, count))
  local rows_needed = math.ceil(count / columns)

  local gap = math.max(0, opts.gap or 1)
  -- Verfügbare Fläche minus der Lücken, aufgeteilt auf die Kacheln.
  local tile_w = math.floor((opts.width - gap * (columns - 1)) / columns)
  local tile_h = math.floor((opts.height - gap * (rows_needed - 1)) / rows_needed)

  -- Unter dieser Größe ist eine Kachel nicht mehr aussagekräftig; dann lieber
  -- weniger Bilder zeigen als alle unlesbar.
  if tile_w < 8 or tile_h < 4 then
    return placements, count
  end

  local skipped = 0
  for i, file in ipairs(files) do
    local index = i - 1
    local grid_row = math.floor(index / columns)
    local grid_col = index % columns

    local row = opts.top + grid_row * (tile_h + gap)
    local col = opts.left + grid_col * (tile_w + gap)

    if row + tile_h - 1 > opts.top + opts.height - 1 then
      skipped = skipped + 1
    else
      placements[#placements + 1] = {
        file = file,
        row = row,
        col = col,
        cols = tile_w,
        rows = tile_h,
      }
    end
  end

  return placements, skipped
end

return M
