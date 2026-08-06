---@module 'images.browse'
---@brief Bilder in einem Verzeichnisbaum finden und mit Live-Vorschau auswählen.
---@description
--- Anders als `images.scan` (Bildlinks *eines Buffers*) durchsucht dieses
--- Modul das Dateisystem selbst: alle Bilddateien unterhalb eines Root, egal
--- ob irgendwo verlinkt. Drei Scopes lösen den Root auf — `cfile` (Verzeichnis
--- der aktuellen Datei), `cwd`, `path <dir>` (explizit).
---
--- Kein Dep auf pickers.nvim: dessen Engine-Abstraktion (telescope/fzf-lua/
--- snacks einheitlich) hat keinen Weg, eine plugin-eigene Live-Vorschau über
--- alle drei Engines zu legen — nur snacks erlaubt eine custom
--- `preview`-Funktion pro Picker. Da genau diese Live-Vorschau der Punkt
--- dieses Features ist, bindet dieses Modul direkt an `snacks.picker` (Soft-
--- Dependency, gleiches Muster wie `images.bindings.which_key`) und fällt
--- ohne snacks auf eine einfache Auswahl ohne Vorschau zurück.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Verzeichnisnamen, die immer übersprungen werden — unabhängig von
--- `display.browse_exclude`, das der User zusätzlich erweitern kann.
---@type table<string, boolean>
local ALWAYS_EXCLUDE = { [".git"] = true }

--- Obergrenze besuchter Einträge, als Sicherheitsnetz gegen einen riesigen
--- `cwd`-Scan (z.B. versehentlich im Home-Verzeichnis). Kein Fehler, nur ein
--- stiller Stopp — die Trefferliste bis dahin ist immer noch brauchbar.
local MAX_ENTRIES = 20000

--- Bilddateien unterhalb `root` einsammeln (Breitensuche, iterativ statt
--- rekursiv — vermeidet Stack-Tiefe bei sehr verschachtelten Bäumen).
---@param root string absoluter Pfad
---@param exclude string[]|nil zusätzliche Verzeichnisnamen zum Überspringen
---@param extensions string[] erlaubte Endungen, ohne Punkt
---@return string[] gefundene Bildpfade, sortiert
local function walk(root, exclude, extensions)
  local exclude_set = vim.deepcopy(ALWAYS_EXCLUDE)
  for _, name in ipairs(exclude or {}) do
    exclude_set[name] = true
  end

  local ext_set = {}
  for _, e in ipairs(extensions) do
    ext_set[e:lower()] = true
  end

  local found = {}
  local visited = 0
  local stack = { root }

  while #stack > 0 do
    local dir = table.remove(stack)
    local handle = vim.uv.fs_scandir(dir)
    if handle then
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then break end
        visited = visited + 1
        if visited > MAX_ENTRIES then
          table.sort(found)
          return found
        end
        if kind == "directory" then
          if not exclude_set[name] then stack[#stack + 1] = dir .. "/" .. name end
        elseif kind == "file" then
          local ext = name:match("%.([%w]+)$")
          if ext and ext_set[ext:lower()] then found[#found + 1] = dir .. "/" .. name end
        end
      end
    end
  end

  table.sort(found)
  return found
end
-- Für Tests exponiert: reine Funktion, kein Terminal nötig.
M.walk = walk

--- Bilddateien unterhalb `root` sammeln, mit der konfigurierten
--- Ausschlussliste und den konfigurierten Endungen.
---@param root string absoluter Verzeichnispfad
---@return string[] absolute Pfade, sortiert
function M.scan(root)
  local c = cfg()
  return walk(root, c.display.browse_exclude, c.extensions)
end

--- Scope-Argument zu einem einzelnen Root-Verzeichnis auflösen.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil bei scope="path": das Zielverzeichnis
---@return string|nil root normalisiert (siehe `images.resolve.normalize_path`)
---@return string|nil err
function M.roots(scope, arg)
  scope = scope or "cwd"
  local resolve = require("images.resolve")

  if scope == "path" then
    if not arg or arg == "" then return nil, "`path`-Scope braucht ein Verzeichnis: :Image pickers path <dir>" end
    local expanded = vim.fn.fnamemodify(vim.fn.expand(arg), ":p")
    if vim.fn.isdirectory(expanded) == 0 then return nil, "Kein Verzeichnis: " .. arg end
    return resolve.normalize_path(expanded)
  end

  if scope == "cfile" then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then return nil, "Aktueller Buffer hat keinen Dateipfad" end
    return resolve.normalize_path(vim.fn.fnamemodify(name, ":p:h"))
  end

  if scope == "cwd" then return resolve.normalize_path(vim.uv.cwd() or vim.fn.getcwd()) end

  return nil, "Unbekannter Scope: " .. tostring(scope) .. " (erwartet cfile|cwd|path)"
end

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@return table|nil snacks.picker, falls installiert
local function snacks_picker()
  local ok, picker = pcall(require, "snacks.picker")
  return (ok and type(picker) == "table") and picker or nil
end

--- Ob `snacks.picker` verfügbar ist — für `:checkhealth images`.
---@return boolean
function M.snacks_available()
  return snacks_picker() ~= nil
end

--- Ein Bild anhand der Geometrie eines Fensters zeichnen, statt anhand der
--- Cursorposition (anders als `images.show`) — für die Vorschau innerhalb
--- eines Picker-Fensters, dessen Lage der Aufrufer nicht selbst kennt.
---@param file string
---@param winid integer
---@param factor number|nil 0 < factor <= 1; nil/1 = volle Fenstergröße.
---            Kleiner als 1 zentriert eine entsprechend kleinere Box im
---            Fenster, statt es zu füllen — siehe `images.scale`, das für
---            `:Image compare` den Faktor aus den echten Bildmaßen ableitet.
---@return boolean ok
local function draw_in_window(file, winid, factor)
  if not vim.api.nvim_win_is_valid(winid) then return false end
  local pos = vim.api.nvim_win_get_position(winid)
  local width = vim.api.nvim_win_get_width(winid)
  local height = vim.api.nvim_win_get_height(winid)
  require("images.terminal").clear()

  local cols, rows, col_off, row_off = width, height, 0, 0
  if factor and factor < 1 then
    cols, rows, col_off, row_off = require("images.scale").box(width, height, factor)
  end

  local ok = require("images.terminal").draw(file, pos[1] + 1 + row_off, pos[2] + 1 + col_off, cols, rows)
  return ok
end
M.draw_in_window = draw_in_window

--- Picker mit Live-Bildvorschau über `snacks.picker` öffnen.
---@param root string
---@param files string[]
local function open_snacks(root, files)
  local Picker = snacks_picker()
  if not Picker then
    notify().error("snacks.picker nicht verfügbar")
    return
  end

  local items = {}
  for i, path in ipairs(files) do
    items[i] = { text = path, file = path }
  end

  Picker.pick({
    source = "images_browse",
    title = "Bilder: " .. root,
    items = items,
    format = "file",
    preview = function(ctx)
      ctx.preview:reset()
      if not draw_in_window(ctx.item.file, ctx.win) then ctx.preview:notify("Bild kann hier nicht gezeichnet werden", "warn") end
    end,
    -- `<Tab>` ist snacks' eigene Multi-Select-Taste (nicht von images.nvim
    -- verdrahtet). `picker:selected({fallback=true})` liefert die markierten
    -- Treffer, oder — ohne Markierung — den einen hervorgehobenen: mehrere
    -- Bilder ergeben eine Galerie, ein einzelnes die normale Einzelanzeige.
    confirm = function(picker, item)
      local selected = picker:selected({ fallback = true })
      picker:close()
      if #selected > 1 then
        local paths = {}
        for i, sel in ipairs(selected) do
          paths[i] = sel.file
        end
        require("images").gallery(paths)
      elseif item then
        require("images").show(item.file)
      end
    end,
    -- Das Overlay hängt am Terminal, nicht am Picker-Fenster — beim Schließen
    -- (egal ob per Auswahl oder Esc) bleibt es sonst hängen bis zum nächsten
    -- vollen Repaint.
    on_close = function()
      require("images.terminal").clear()
    end,
  })
end

--- Fallback ohne snacks: einfache Auswahl ohne Live-Vorschau, gleiches
--- Muster wie `images.list`.
---@param root string
---@param files string[]
local function open_select(root, files)
  ---@param path string
  local function format_item(path)
    return path:sub(#root + 2)
  end

  local function on_pick(choice)
    if choice then require("images").show(choice) end
  end

  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if ok and kit.select then
    kit.select({ items = files, title = "Bilder: " .. root, format_item = format_item, on_select = on_pick })
    return
  end

  vim.ui.select(files, { prompt = "Bild anzeigen", format_item = format_item }, on_pick)
end

--- Bilder unterhalb eines Scopes durchsuchen und eines zur Anzeige auswählen.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil bei scope="path": das Zielverzeichnis
---@return nil
function M.open(scope, arg)
  local root, err = M.roots(scope, arg)
  if not root then
    notify().warn(err or "Kein Root gefunden")
    return
  end

  local files = M.scan(root)
  if #files == 0 then
    notify().info("Keine Bilder gefunden unter: " .. root)
    return
  end

  require("images.guard").check()

  if M.snacks_available() then
    open_snacks(root, files)
  else
    open_select(root, files)
  end
end

return M
