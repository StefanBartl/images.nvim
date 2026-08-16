---@module 'images.remote'
---@brief Bild von einer http(s)-URL laden und cachen.
---@description
--- Standardmäßig AUS: Ein Markdown-Dokument mit einem Remote-Bild-Link würde
--- sonst schon beim bloßen Hover eine ausgehende Netzwerkanfrage auslösen —
--- genau das Verhalten, das E-Mail-Clients seit Jahren aus
--- Datenschutzgründen standardmäßig blockieren ("externe Bilder laden").
--- `display.remote.enabled = true` schaltet es bewusst ein.
---
--- Greift nur beim expliziten Anzeigen eines einzelnen Bildes (`:Image show`,
--- Hover), nicht beim Scannen (`:Image list`/`gallery`/`next`/`prev`/
--- `orphans`, `images.resolve.to_path`) — sonst würde ein bloßes Auflisten
--- der Bilder eines Buffers N Netzwerkanfragen auslösen, nur um eine Liste
--- zu zeigen. `:Image gallery`/`compare`/`browse`/`zen` unterstützen
--- Remote-Bilder aus demselben Grund (noch) nicht — offene Arbeit, siehe
--- docs/ROADMAP/FEATURES.md.

local M = {}

--- Ob `target` wie eine ladbare Remote-URL aussieht. Bewusst nur http(s) —
--- andere Schemata (`ftp://`, `file://`, …) bräuchten andere Werkzeuge und
--- sind für Markdown-Bildlinks nicht der praktische Fall.
---@param target string
---@return boolean
function M.is_remote(target)
  return target:match("^https?://") ~= nil
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/remote"
  require("lib.nvim.fs.mkdirp")(dir)
  return dir
end

--- Cache-Pfad für eine URL: Hash der URL, mit der Endung aus dem Pfadanteil
--- (ohne Query/Fragment), falls erkennbar. WezTerm erkennt das Bildformat
--- ohnehin an den Bytes; die Endung wird nur gebraucht, damit eine
--- `.svg`-URL nach dem Download weiter als SVG erkannt und konvertiert wird
--- (siehe `images.convert`, `images.terminal`'s Zeichenpfad).
---@param url string
---@return string
local function cache_path(url)
  local key = vim.fn.sha256(url)
  local path_part = url:gsub("[?#].*$", "")
  local ext = path_part:match("%.([%w]+)$")
  return cache_dir() .. "/" .. key .. (ext and ("." .. ext:lower()) or "")
end

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Bild von `url` laden, gecacht — ein zweiter Aufruf mit derselben URL
--- lädt nicht erneut, sondern trifft den Cache.
---@param url string
---@return string|nil local_path
---@return string|nil err
function M.fetch(url)
  local c = cfg().display.remote
  if not c.enabled then return nil, "Remote-Bilder sind deaktiviert (`display.remote.enabled = true` zum Einschalten)" end

  local out = cache_path(url)
  if vim.uv.fs_stat(out) then return out end

  local timeout_s = math.max(1, math.floor((c.timeout_ms or 10000) / 1000))
  local max_bytes = c.max_bytes or (20 * 1024 * 1024)

  local executable = require("lib.nvim.cross.executable")
  local cmd
  if executable.exists("curl") then
    cmd = {
      "curl",
      "-fsSL",
      "--max-time",
      tostring(timeout_s),
      "--max-filesize",
      tostring(max_bytes),
      "-o",
      out,
      url,
    }
  elseif executable.exists("wget") then
    -- -Q<bytes>: Quota, das nächstbeste Aequivalent zu curls --max-filesize.
    cmd = { "wget", "-q", "--timeout=" .. tostring(timeout_s), "-Q" .. tostring(max_bytes), "-O", out, url }
  else
    return nil, "Weder `curl` noch `wget` gefunden"
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    pcall(vim.uv.fs_unlink, out)
    return nil, ("Download fehlgeschlagen (exit %d): %s"):format(result.code, vim.trim(result.stderr or ""))
  end

  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    return nil, "Download lieferte keine Datei"
  end

  return out
end

return M
