---@module 'images'
---@brief Einstiegspunkt für images.nvim — `:Image` und die öffentliche Lua-API.
---@description
--- Bilder im Terminal anzeigen, ohne dass Neovim das Terminal verlässt.
---
--- Der Unterschied zu snacks.image und image.nvim: beide sprechen ausschließlich
--- das Kitty-Graphics-Protokoll. Auf nativem Windows-Neovim in WezTerm wird das
--- aus Neovim heraus nie gezeichnet — dieses Plugin nutzt stattdessen das
--- iTerm2-Protokoll (OSC 1337), das dort zuverlässig funktioniert.
---
--- Alle Anzeigefunktionen geben `boolean` zurück und melden Fehler über
--- `lib.nvim.notify`. Die Low-Level-Module (`terminal`, `gallery`, `info`)
--- benachrichtigen nie selbst, sondern liefern `ok, err` — die Entscheidung,
--- ob ein Fehler den User erreicht, fällt hier.
---@see images.terminal für die Protokoll-Details und die Fallstricke
---@see images.gallery für die Rasteraufteilung mehrerer Bilder
---@see images.paste für den Zwischenablage-Workflow

local M = {}

--- Zuletzt angezeigtes Ziel, für `:Image next`/`prev`.
---@type { buf: integer, index: integer }|nil
local cursor_state = nil

--- Ob das aktuelle Bild angeheftet ist (kein automatisches Aufräumen).
---@type boolean
local pinned = false

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Optionales UI-Kit aus lib.nvim. Fehlt es, fallen die Aufrufer auf die
--- Neovim-Bordmittel zurück — das Kit ist Komfort, keine Voraussetzung.
---@return table|nil
local function kit()
  local ok, k = pcall(require, "lib.nvim.ui.kit")
  return ok and k or nil
end

--- Autocmds registrieren, die ein angezeigtes Bild wieder entfernen.
--- Bei angehefteten Bildern (`M.pin`) passiert nichts.
---@return nil
local function arm_clear()
  if pinned then
    return
  end
  local events = cfg().display.clear_events
  if not events or #events == 0 then
    return
  end
  vim.api.nvim_create_autocmd(events, {
    group = vim.api.nvim_create_augroup("images.clear", { clear = true }),
    once = true,
    callback = function()
      require("images.terminal").clear()
    end,
  })
end

--- Guard vor dem ersten Zeichnen: kann dieses Terminal überhaupt Bilder?
--- Gemeinsam mit `images.browse`/`images.zen`, die denselben Zeichenpfad vor
--- sich haben — siehe `images.guard` für die Begründung.
---@return nil
local function guard_capability()
  require("images.guard").check()
end

--- Startzeile so wählen, dass ein Block der Höhe `rows` noch auf den Schirm
--- passt. Ohne die Deckelung rutscht ein hohes Bild unter den unteren Rand.
---@param rows integer
---@return integer
local function row_below_cursor(rows)
  local screen_row = vim.fn.screenrow()
  return math.max(1, math.min(screen_row + 1, vim.o.lines - rows - 1))
end

-- ── Anzeige ──────────────────────────────────────────────────────────────────

--- Eine Bilddatei anzeigen.
---@param path string Absoluter oder relativer Pfad
---@return boolean ok
function M.show(path)
  guard_capability()

  local file = require("images.resolve").to_path(path)
  if not file then
    notify().error("Bild nicht gefunden: " .. tostring(path))
    return false
  end

  local display = cfg().display
  local ok, err = require("images.terminal").draw(
    file,
    row_below_cursor(display.max_rows),
    1,
    display.max_cols,
    display.max_rows
  )
  if not ok then
    notify().error(err or "Anzeige fehlgeschlagen")
    return false
  end

  arm_clear()
  return true
end

--- Bild unter dem Cursor anzeigen (Markdown-Link oder Dateiname).
---@return boolean ok
function M.hover()
  local target, err = require("images.resolve").under_cursor()
  if not target then
    notify().warn(err or "Kein Bild unter dem Cursor")
    return false
  end
  return M.show(target.path)
end

--- Mehrere Bilder nebeneinander anzeigen.
---@param paths string[]|nil Absolute Pfade; nil = alle Bilder des Buffers
---@param columns integer|nil Spaltenzahl; nil = automatisch
---@return boolean ok
function M.gallery(paths, columns)
  if not paths then
    local found = require("images.scan").buffer(0)
    paths = {}
    for _, t in ipairs(found) do
      paths[#paths + 1] = t.path
    end
  end

  if #paths == 0 then
    notify().info("Keine Bilder zum Anzeigen")
    return false
  end

  guard_capability()

  local display = cfg().display
  -- Die Galerie darf mehr Fläche belegen als eine Einzelanzeige: sie ist der
  -- explizite Übersichtsmodus, nicht der beiläufige Blick.
  local height = math.max(6, math.floor(vim.o.lines * 0.7))
  local placements, skipped = require("images.gallery").layout(paths, {
    columns = columns,
    gap = display.gallery_gap,
    top = math.max(1, math.floor((vim.o.lines - height) / 2)),
    left = 1,
    width = vim.o.columns - 2,
    height = height,
  })

  if #placements == 0 then
    notify().warn("Zu wenig Platz für eine Galerie — Fenster vergrößern oder weniger Bilder")
    return false
  end

  local drawn, errors = require("images.terminal").draw_many(placements)
  if drawn == 0 then
    notify().error(errors[1] or "Galerie konnte nicht gezeichnet werden")
    return false
  end

  if skipped > 0 or #errors > 0 then
    notify().warn(("%d von %d Bildern nicht gezeigt"):format(skipped + #errors, #paths))
  end

  arm_clear()
  return true
end

--- Bilder eines Zeilenbereichs nebeneinander anzeigen. Dünner Wrapper um
--- `M.gallery`, der den Range in Ziele auflöst — für `:'<,'>Image gallery`
--- und den Range-Fall der bare `:Image` (siehe `bindings/usrcmds.lua`).
---@param first integer 1-basierte Startzeile
---@param last integer 1-basierte Endzeile
---@param columns integer|nil Spaltenzahl; nil = automatisch
---@return boolean ok
function M.gallery_range(first, last, columns)
  local found = require("images.scan").buffer(0, first, last)
  local paths = {}
  for _, t in ipairs(found) do
    paths[#paths + 1] = t.path
  end
  if #paths == 0 then
    notify().info("Keine Bilder in diesem Bereich")
    return false
  end
  return M.gallery(paths, columns)
end

--- Bilder des Buffers auflisten und eines zur Anzeige auswählen.
--- Nutzt das UI-Kit aus lib.nvim, falls vorhanden, sonst `vim.ui.select`.
---@param first integer|nil 1-basierte Startzeile (für `:'<,'>Image list`)
---@param last integer|nil 1-basierte Endzeile
---@return nil
function M.list(first, last)
  local found, missing = require("images.scan").buffer(0, first, last)

  if #missing > 0 then
    notify().warn(("%d Bildlink(s) nicht auflösbar, z.B. %s"):format(#missing, missing[1]))
  end
  if #found == 0 then
    notify().info("Keine Bilder in diesem Buffer")
    return
  end
  if #found == 1 then
    M.show(found[1].path)
    return
  end

  ---@param item ImagesNvim.Target
  local function format_item(item)
    return ("%4d  %s"):format(item.lnum, item.raw)
  end

  local k = kit()
  if k and k.select then
    k.select({
      items = found,
      title = "Bilder in diesem Buffer",
      format_item = format_item,
      on_select = function(choice)
        if choice then
          M.show(choice.path)
        end
      end,
    })
    return
  end

  vim.ui.select(found, { prompt = "Bild anzeigen", format_item = format_item }, function(choice)
    if choice then
      M.show(choice.path)
    end
  end)
end

--- Zum nächsten/vorherigen Bild des Buffers springen und es anzeigen.
---@param delta integer 1 = weiter, -1 = zurück
---@return boolean ok
function M.step(delta)
  local buf = vim.api.nvim_get_current_buf()
  local found = require("images.scan").buffer(buf)
  if #found == 0 then
    notify().info("Keine Bilder in diesem Buffer")
    return false
  end

  local index
  if cursor_state and cursor_state.buf == buf then
    index = cursor_state.index + delta
  else
    -- Erster Aufruf im Buffer: beim Bild starten, das dem Cursor am nächsten
    -- liegt, statt stumpf bei 1 — sonst springt man aus der Mitte eines langen
    -- Dokuments unerwartet an den Anfang.
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    index = 1
    for i, t in ipairs(found) do
      if t.lnum <= lnum then
        index = i
      end
    end
    if delta > 0 and found[index] and found[index].lnum <= lnum then
      index = index + delta
    end
  end

  -- Umlaufen statt an den Enden anzustoßen.
  index = ((index - 1) % #found) + 1
  cursor_state = { buf = buf, index = index }

  local target = found[index]
  -- Der Scan lief über den Buffer-Inhalt; die Zeile kann durch eine
  -- zwischenzeitliche Änderung außerhalb des gültigen Bereichs liegen.
  local line_count = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(target.lnum, line_count), 0 })
  return M.show(target.path)
end

-- ── Metadaten, Zwischenablage, Aufräumen ─────────────────────────────────────

--- Metadaten eines Bildes anzeigen.
---@param path string|nil nil = Bild unter dem Cursor
---@return boolean ok
function M.info(path)
  local file
  if path then
    file = require("images.resolve").to_path(path)
  else
    local target = require("images.resolve").under_cursor()
    file = target and target.path
  end
  if not file then
    notify().warn("Kein Bild gefunden")
    return false
  end

  local data, err = require("images.info").collect(file)
  if not data then
    notify().error(err or "Metadaten nicht lesbar")
    return false
  end

  local lines = require("images.info").lines(data)
  local k = kit()
  if k and k.viewer then
    k.viewer({ title = "Bildinfo", message = lines })
  else
    notify().info(table.concat(lines, "\n"))
  end
  return true
end

--- Bild aus der Zwischenablage speichern und verlinken.
---@return nil
function M.paste()
  require("images.paste").run()
end

--- Bestehendes Bild durch den Zwischenablage-Inhalt ersetzen, ohne den Link
--- zu ändern.
---@param path string|nil nil = Bild unter dem Cursor
---@return nil
function M.replace(path)
  require("images.paste").replace(path)
end

--- Bilddateien im Zielverzeichnis finden, auf die kein Link mehr zeigt, und
--- eine zum Löschen anbieten. Löscht ausschließlich nach expliziter
--- Bestätigung — verwaiste Bilder zu *finden* soll risikofrei sein, auch
--- wenn `:Image orphans` versehentlich zweimal ausgeführt wird.
---@return nil
function M.orphans()
  local orphans = require("images.orphans").find()
  if #orphans == 0 then
    notify().info("Keine verwaisten Bilder gefunden")
    return
  end

  ---@param o Images.Orphan
  local function format_item(o)
    return o.rel
  end

  ---@param choice Images.Orphan|nil
  local function on_pick(choice)
    if not choice then
      return
    end

    ---@param confirmed boolean
    local function delete_if_confirmed(confirmed)
      if not confirmed then
        return
      end
      local ok = pcall(vim.uv.fs_unlink, choice.path)
      if ok then
        notify().info("Gelöscht: " .. choice.rel)
      else
        notify().error("Löschen fehlgeschlagen: " .. choice.rel)
      end
    end

    local k = kit()
    if k and k.confirm then
      -- Explizite `choices`: ohne sie liefert `on_answer` ein boolean statt
      -- des Labels (siehe kit.confirm's M.confirm — `custom` schaltet
      -- zwischen beidem um), und die Buttons zeigen sonst engl. "Yes"/"No".
      k.confirm({
        question = ("'%s' löschen?"):format(choice.rel),
        choices = { "Ja", "Nein" },
        on_answer = function(answer)
          delete_if_confirmed(answer == "Ja")
        end,
      })
    else
      delete_if_confirmed(vim.fn.confirm(("'%s' löschen?"):format(choice.rel), "&Ja\n&Nein", 2) == 1)
    end
  end

  local k = kit()
  local title = ("%d verwaiste Bild(er)"):format(#orphans)
  if k and k.select then
    k.select({ items = orphans, title = title, format_item = format_item, on_select = on_pick })
  else
    vim.ui.select(orphans, { prompt = title, format_item = format_item }, on_pick)
  end
end

--- Bilder unterhalb eines Scopes durchsuchen und mit Live-Vorschau (falls
--- snacks.picker installiert ist) auswählen.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil bei scope="path": das Zielverzeichnis
---@return nil
function M.browse(scope, arg)
  require("images.browse").open(scope, arg)
end

--- Bild unter dem Cursor (oder an `path`) in einem großen, editierbaren
--- Fenster anzeigen — bleibt bestehen, auch wenn parallel ein Hover-Popup
--- (z.B. von snacks) aufgeht, siehe `images.zen`.
---@param path string|nil nil = Bild unter dem Cursor
---@return boolean ok
function M.zen(path)
  return require("images.zen").open(path)
end

--- Zwei Bilder unterhalb eines Scopes auswählen und nebeneinander vergleichen.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil bei scope="path": das Zielverzeichnis
---@return nil
function M.compare(scope, arg)
  require("images.compare").open(scope, arg)
end

--- Kurzindikator für die Statusline: leer, wenn kein Bild angezeigt wird.
--- Beispiel für lualine: `{ require("images").statusline }`.
---@param opts { icon?: string, pinned_suffix?: string }|nil
---@return string
function M.statusline(opts)
  opts = opts or {}
  if not require("images.terminal").is_showing() then
    return ""
  end
  local icon = opts.icon or "🖼"
  if pinned then
    return icon .. (opts.pinned_suffix or "📌")
  end
  return icon
end

--- Automatisches Aufräumen für das aktuelle Bild an- oder abschalten.
---@param on boolean|nil nil = umschalten
---@return boolean pinned neuer Zustand
function M.pin(on)
  if on == nil then
    pinned = not pinned
  else
    pinned = on and true or false
  end

  if pinned then
    -- Bereits scharf gestellte Aufräum-Autocmds zurücknehmen, sonst räumt der
    -- nächste Cursorsprung das gerade angeheftete Bild trotzdem weg.
    pcall(vim.api.nvim_del_augroup_by_name, "images.clear")
    notify().info("Bild angeheftet — `:Image clear` entfernt es")
  else
    notify().info("Bild wird bei der nächsten Cursorbewegung entfernt")
    arm_clear()
  end
  return pinned
end

--- Angezeigte Bilder entfernen, inklusive eines offenen Zen-Fensters.
---@return nil
function M.clear()
  pinned = false
  cursor_state = nil
  require("images.zen").close()
  require("images.terminal").clear()
end

--- Fähigkeitsprüfung erneut durchführen. Nötig, wenn `assume_supported`
--- nachträglich gesetzt wurde — sonst gilt das gemerkte Ergebnis weiter.
---@return Images.Capability
function M.recheck()
  require("images.guard").reset()
  require("images.terminal").reset_capability()
  local cap = require("images.terminal").capability(require("images.config").get().display.assume_supported)
  if cap.ok then
    notify().info("Bildausgabe verfügbar" .. (cap.terminal and (" (" .. cap.terminal .. ")") or ""))
  else
    notify().warn(table.concat({ cap.reason or "", cap.hint or "" }, "\n"))
  end
  return cap
end

--- Plugin einrichten.
---@param opts table|nil siehe `images.config.DEFAULTS`
---@return nil
function M.setup(opts)
  local conf = require("images.config").setup(opts)
  require("images.bindings.usrcmds").register(conf)
  require("images.bindings.keymaps").register(conf)
  require("images.bindings.autocmds").register(conf)
end

return M
