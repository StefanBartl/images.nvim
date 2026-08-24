---@module 'images.calibration'
---@brief Eingemessene Werte über Neustarts hinweg festhalten.
---@description
--- `:Image calibrate` ermittelt Werte, die für *diese* Terminal-Installation
--- gelten — nicht für das Plugin und nicht für ein Projekt. Sie gehören
--- deshalb weder in die Repo-Konfiguration noch in eine
--- `setup()`-Spec, die der User womöglich zwischen Rechnern synchronisiert:
--- dasselbe `terminal_padding` wäre auf dem anderen Rechner mit anderer
--- Schriftgröße schlicht falsch.
---
--- Also `stdpath("data")`, wo maschinenlokaler Zustand hingehört, und
--- bewusst **nicht** die User-Spec editieren. Ein Plugin, das ungefragt in
--- fremde Konfigurationsdateien schreibt, ist ein Plugin, dem man beim
--- nächsten Update misstraut — und ein Merge-Konflikt in einer
--- versionierten Dotfile-Sammlung wäre ein schlechter Dank für eine
--- Kalibrierung.
---
--- **Rangfolge.** Defaults < gespeicherte Kalibrierung < explizite
--- `setup()`-Optionen. Wer einen Wert selbst in die Spec schreibt, hat immer
--- recht: er hat sich entschieden, die Kalibrierung ist nur eine Messung.
--- `:Image calibrate` weist darauf hin, wenn eine solche Option den
--- gemessenen Wert überstimmt — still übergangen zu werden wäre die
--- schlechteste Variante.

local M = {}

---@internal
---@return string dir
local function dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "images.nvim")
end

--- Pfad der Kalibrierdatei.
---@return string
function M.path()
  return vim.fs.joinpath(dir(), "calibration.json")
end

---@type table|nil
local cached = nil
---@type boolean
local loaded = false

--- Gespeicherte Werte lesen. Fehlt die Datei oder ist sie unlesbar, ist das
--- kein Fehlerfall, sondern der Normalzustand vor der ersten Kalibrierung.
---@param force boolean|nil gemerktes Ergebnis verwerfen
---@return table values leer, wenn nichts gespeichert ist
function M.load(force)
  if loaded and not force then return cached or {} end
  loaded = true
  cached = {}

  local f = io.open(M.path(), "r")
  if not f then return cached end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then return cached end

  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then cached = decoded end
  return cached
end

--- Werte speichern. Bestehende Einträge bleiben erhalten, damit eine
--- Teilkalibrierung nicht eine frühere vollständige überschreibt.
---@param values table
---@return boolean ok
---@return string|nil err
function M.save(values)
  if type(values) ~= "table" then return false, "keine Werte übergeben" end

  local merged = vim.tbl_deep_extend("force", M.load(true), values)

  local ok_mk = vim.fn.mkdir(dir(), "p")
  if ok_mk == 0 and vim.fn.isdirectory(dir()) == 0 then return false, "Verzeichnis nicht anlegbar: " .. dir() end

  local ok_enc, encoded = pcall(vim.json.encode, merged)
  if not ok_enc then return false, "nicht serialisierbar: " .. tostring(encoded) end

  local f, ferr = io.open(M.path(), "w")
  if not f then return false, tostring(ferr) end
  f:write(encoded)
  f:close()

  cached, loaded = merged, true
  return true
end

--- Gespeicherte Werte verwerfen.
---@return boolean ok
function M.clear()
  cached, loaded = {}, true
  local ok = os.remove(M.path())
  return ok ~= nil or vim.fn.filereadable(M.path()) == 0
end

--- Die Kalibrierung als `display`-Teiltabelle, wie `config.setup` sie
--- erwartet. Leer, wenn nichts gespeichert ist — dann verhält sich alles wie
--- ohne dieses Modul.
---@return table
function M.as_config()
  local values = M.load()
  if vim.tbl_isempty(values) then return {} end
  return { display = values }
end

return M
