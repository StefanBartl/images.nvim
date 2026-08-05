---@module 'images.resolve'
---@brief Bildziele im Buffer finden und zu absoluten Pfaden auflösen.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Ob ein Ziel nach einer Bilddatei aussieht (rein anhand der Endung).
---@param target string
---@return boolean
function M.is_image(target)
  local ext = target:match("%.([%w]+)%s*$") or target:match("%.([%w]+)[?#]")
  if not ext then
    return false
  end
  ext = ext:lower()
  for _, e in ipairs(cfg().extensions) do
    if e == ext then
      return true
    end
  end
  return false
end

--- Alle Markdown-Link-Ziele einer Zeile mit ihren Spaltenbereichen.
---@param line string
---@return { target: string, from: integer, to: integer }[]
function M.links_in_line(line)
  local out = {}
  local init = 1
  while true do
    local s, e, target = line:find("%]%(([^)]+)%)", init)
    if not s then
      break
    end
    -- Beginn des Links inklusive `![alt` bzw. `[text`, damit der Cursor
    -- irgendwo im Link genügt und nicht nur im Klammerteil stehen muss.
    local from = line:sub(1, s):find("!?%[[^%[]*$") or s
    out[#out + 1] = { target = target, from = from, to = e }
    init = e + 1
  end
  return out
end

--- Relativen Pfad auflösen. Nutzt den Resolver aus markdown.nvim, falls
--- vorhanden — der kennt bereits mehrere Basisverzeichnisse und normalisiert
--- Windows-Pfade korrekt. Sonst Buffer-Verzeichnis, dann cwd.
---@param target string
---@param buf integer|nil Buffer, gegen dessen Verzeichnis aufgelöst wird
---@return string|nil absoluter Pfad, falls die Datei existiert
function M.to_path(target, buf)
  if target:match("^%a+://") then
    return nil -- Remote-URLs werden (noch) nicht geladen
  end

  local ok, path_util = pcall(require, "markdown.util.path")
  if ok and type(path_util.resolve) == "function" then
    local resolved = path_util.resolve(target)
    if resolved and vim.uv.fs_stat(resolved) then
      return resolved
    end
  end

  local expanded = vim.fn.expand(target)
  if vim.uv.fs_stat(expanded) then
    return vim.fn.fnamemodify(expanded, ":p")
  end

  local bases = {}
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name ~= "" then
    bases[#bases + 1] = vim.fn.fnamemodify(name, ":p:h")
  end
  bases[#bases + 1] = vim.uv.cwd()

  for _, base in ipairs(bases) do
    if base and base ~= "" then
      local candidate = base .. "/" .. expanded
      if vim.uv.fs_stat(candidate) then
        return vim.fn.fnamemodify(candidate, ":p")
      end
    end
  end
  return nil
end

--- Bildziel unter dem Cursor: erst Markdown-Links der Zeile, sonst `<cfile>`.
---@return ImagesNvim.Target|nil
---@return string|nil err
function M.under_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1], pos[2] + 1
  local line = vim.api.nvim_get_current_line()

  for _, link in ipairs(M.links_in_line(line)) do
    if col >= link.from and col <= link.to then
      if not M.is_image(link.target) then
        return nil, "Kein Bildlink: " .. link.target
      end
      local path = M.to_path(link.target)
      if not path then
        return nil, "Bild nicht gefunden: " .. link.target
      end
      return { raw = link.target, path = path, lnum = lnum }
    end
  end

  local cfile = vim.fn.expand("<cfile>")
  if cfile == "" then
    return nil, "Kein Link oder Dateiname unter dem Cursor"
  end
  if not M.is_image(cfile) then
    return nil, "Keine Bilddatei: " .. cfile
  end
  local path = M.to_path(cfile)
  if not path then
    return nil, "Bild nicht gefunden: " .. cfile
  end
  return { raw = cfile, path = path, lnum = lnum }
end

return M
