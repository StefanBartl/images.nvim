---@module 'images.info'
---@brief Metadaten einer Bilddatei ermitteln.
---@description
--- Format und Abmessungen kommen von ImageMagick, falls vorhanden. Ohne
--- ImageMagick bleiben Größe und Änderungsdatum — nutzlos wird das Feature
--- dadurch nicht, deshalb ist `magick` bewusst optional.

local M = {}

---@class Images.Info
---@field path string Absoluter Pfad
---@field bytes integer Dateigröße
---@field mtime integer Änderungszeitpunkt (Unix)
---@field format string|nil z.B. "PNG"
---@field width integer|nil Pixel
---@field height integer|nil Pixel

--- Bytes menschenlesbar formatieren.
---@param bytes integer
---@return string
function M.human_size(bytes)
  local units = { "B", "KB", "MB", "GB" }
  local value, unit = bytes, 1
  while value >= 1024 and unit < #units do
    value = value / 1024
    unit = unit + 1
  end
  if unit == 1 then
    return ("%d %s"):format(value, units[unit])
  end
  return ("%.1f %s"):format(value, units[unit])
end

--- Metadaten sammeln.
---@param path string Absoluter Pfad
---@return Images.Info|nil
---@return string|nil err
function M.collect(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil, "Datei nicht gefunden: " .. path
  end

  ---@type Images.Info
  local info = {
    path = path,
    bytes = stat.size,
    mtime = stat.mtime and stat.mtime.sec or 0,
  }

  if vim.fn.executable("magick") == 1 then
    -- `identify` als Subcommand von `magick`, nicht als eigenes Binary: auf
    -- Windows kollidiert `convert.exe`/`identify.exe` mit den gleichnamigen
    -- Systemprogrammen in System32.
    local res = vim.system({ "magick", "identify", "-format", "%m %w %h", path .. "[0]" }, { text = true }):wait()
    if res.code == 0 and res.stdout then
      local fmt, w, h = res.stdout:match("^(%S+)%s+(%d+)%s+(%d+)")
      info.format = fmt
      info.width = tonumber(w)
      info.height = tonumber(h)
    end
  end

  return info
end

--- Metadaten als Zeilen für eine Anzeige.
---@param info Images.Info
---@return string[]
function M.lines(info)
  local out = {
    "Pfad:    " .. vim.fn.fnamemodify(info.path, ":~"),
    "Größe:   " .. M.human_size(info.bytes),
  }
  if info.width and info.height then
    table.insert(out, 2, ("Format:  %s %dx%d"):format(info.format or "?", info.width, info.height))
  elseif vim.fn.executable("magick") == 0 then
    out[#out + 1] = "Format:  (ImageMagick nicht installiert)"
  end
  if info.mtime > 0 then
    out[#out + 1] = "Geändert: " .. os.date("%Y-%m-%d %H:%M", info.mtime)
  end
  return out
end

return M
