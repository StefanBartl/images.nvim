---@module 'images.orphans'
---@brief Bilddateien im Zielverzeichnis finden, auf die kein Link mehr zeigt.
---@description
--- Das Gegenstück zu `images.scan`, das unauflösbare Links meldet — hier ist
--- es umgekehrt: Dateien, die niemand mehr referenziert. Betrachtet wird
--- ausschließlich das konfigurierte `paste.dir`, nicht der ganze Baum: das
--- ist das einzige Verzeichnis, in das images.nvim selbst schreibt, und ein
--- Bild irgendwo sonst im Projekt kann aus gutem Grund unverlinkt liegen.

local M = {}

---@class Images.Orphan
---@field path string Absoluter Pfad
---@field rel string Pfad relativ zum Zielverzeichnis

--- Zielverzeichnis wie beim Einfügen bestimmen (Dokumentverzeichnis +
--- `paste.dir`). Normalisiert, damit Pfadvergleiche in `M.find` nicht an
--- gemischten `/`/`\` scheitern (siehe `images.resolve.normalize_path`).
---@param buf integer
---@return string|nil
local function target_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  local resolve = require("images.resolve")
  local doc_dir = resolve.normalize_path(vim.fn.fnamemodify(name, ":p:h"))
  local sub = require("images.config").get().paste.dir or ""
  return (sub ~= "") and (doc_dir .. "/" .. sub) or doc_dir
end

--- Bilddateien in `dir` auflisten. Nicht rekursiv — das Paste-Ziel ist ein
--- flaches Verzeichnis, kein Baum.
---@param dir string Bereits normalisiert (siehe `target_dir`)
---@return string[]
local function list_images(dir)
  local out = {}
  local resolve = require("images.resolve")
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if kind == "file" and resolve.is_image(name) then out[#out + 1] = dir .. "/" .. name end
  end
  return out
end

--- Verwaiste Bilder finden: im Zielverzeichnis vorhanden, aber von keinem
--- Link im Buffer referenziert.
---@param buf integer|nil default: aktueller Buffer
---@return Images.Orphan[]
function M.find(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local dir = target_dir(buf)
  if not dir or vim.fn.isdirectory(dir) == 0 then return {} end

  local referenced = {}
  for _, target in ipairs(require("images.scan").buffer(buf)) do
    referenced[target.path] = true
  end

  local orphans = {}
  for _, path in ipairs(list_images(dir)) do
    if not referenced[path] then orphans[#orphans + 1] = { path = path, rel = path:sub(#dir + 2) } end
  end
  table.sort(orphans, function(a, b)
    return a.rel < b.rel
  end)
  return orphans
end

return M
