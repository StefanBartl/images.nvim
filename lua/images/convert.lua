---@module 'images.convert'
---@brief SVG zu PNG konvertieren, damit OSC 1337 es zeichnen kann.
---@description
--- WezTerm dekodiert PNG/JPEG/GIF/WebP selbst, aber kein SVG — hier ist eine
--- Konvertierung wirklich nötig, nicht nur eine Verbesserung. Das ist bewusst
--- der einzige Fall, in dem `magick` eine Voraussetzung statt einer Zugabe
--- ist (siehe die Leitplanke in docs/ROADMAP/README.md): ohne ImageMagick
--- gibt es schlicht keinen anderen Weg, SVG-Pixel zu bekommen.
---
--- Ergebnisse landen in `stdpath("cache")/images.nvim/svg`, benannt nach
--- Quellpfad + Änderungszeit — ein geändertes SVG bekommt damit automatisch
--- eine neue PNG-Datei statt eine veraltete zu zeigen, ohne dass der Cache
--- je aufgeräumt werden müsste (Neovims Cache-Verzeichnis ist dafür da).

local M = {}

---@param path string
---@return boolean
function M.is_svg(path)
  return (path:match("%.([%w]+)$") or ""):lower() == "svg"
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/svg"
  if vim.fn.isdirectory(dir) == 0 then pcall(vim.fn.mkdir, dir, "p") end
  return dir
end

--- SVG nach PNG konvertieren, mit Cache über Quellpfad + Änderungszeit.
---@param path string absoluter Pfad zu einer .svg-Datei
---@return string|nil png_path
---@return string|nil err
function M.to_png(path)
  if vim.fn.executable("magick") == 0 then return nil, "SVG braucht ImageMagick (`magick` nicht gefunden)" end

  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "Datei nicht gefunden: " .. path end

  -- sha256 aus Pfad+mtime als Dateiname: kollisionsfrei genug für einen
  -- Cache, und ein geändertes SVG bekommt automatisch einen neuen Schlüssel.
  local key = vim.fn.sha256(path .. ":" .. tostring(stat.mtime and stat.mtime.sec or 0))
  local out = cache_dir() .. "/" .. key .. ".png"

  if vim.uv.fs_stat(out) then return out end

  -- -background none: transparenter Hintergrund statt eines erratenen
  -- Weiß/Schwarz, das auf einem farbigen Terminalhintergrund falsch aussähe.
  local result = vim.system({ "magick", path, "-background", "none", out }, { text = true }):wait()
  if result.code ~= 0 then
    pcall(vim.uv.fs_unlink, out)
    return nil, "Konvertierung fehlgeschlagen: " .. vim.trim(result.stderr or "")
  end
  if not vim.uv.fs_stat(out) then return nil, "Konvertierung lieferte keine Datei" end
  return out
end

return M
