---@module 'images.gallery'
---@brief Show several images side by side at once.
---@description
--- A purely computational module: it distributes N images over a grid and
--- returns placements for `images.terminal.draw_many`. No window, no state, no
--- side effects — which makes the layout testable without a terminal.

local M = {}

---@class Images.Gallery.Opts
---@field columns integer|nil column count; nil = derived from the number of images
---@field gap integer cells of spacing between tiles
---@field top integer 1-based starting row
---@field left integer 1-based starting column
---@field width integer available width in cells
---@field height integer available height in cells

--- Estimate the column count when none was given.
--- The aim is a grid as square as possible, capped at 4 columns — beyond that
--- the tiles become too narrow in a typical terminal to make anything out.
---@param count integer
---@return integer
local function auto_columns(count)
  if count <= 1 then return 1 end
  local cols = math.ceil(math.sqrt(count))
  return math.max(1, math.min(cols, 4))
end

--- Distribute images over a grid.
---@param files string[] absolute paths
---@param opts Images.Gallery.Opts
---@return Images.Placement[] placements
---@return integer skipped number of images there was no room left for
function M.layout(files, opts)
  local placements = {}
  local count = #files
  if count == 0 then return placements, 0 end

  local columns = opts.columns or auto_columns(count)
  columns = math.max(1, math.min(columns, count))
  local rows_needed = math.ceil(count / columns)

  local gap = math.max(0, opts.gap or 1)
  -- Available area minus the gaps, divided among the tiles.
  local tile_w = math.floor((opts.width - gap * (columns - 1)) / columns)
  local tile_h = math.floor((opts.height - gap * (rows_needed - 1)) / rows_needed)

  -- Below this size a tile no longer says anything; better to show fewer
  -- images than to show them all illegibly.
  if tile_w < 8 or tile_h < 4 then return placements, count end

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
