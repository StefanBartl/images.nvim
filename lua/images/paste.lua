---@module 'images.paste'
---@brief Bild aus der Zwischenablage als Datei ablegen und den Link einfügen.
---@description
--- Der Alltagsfall für Dokumentation: Screenshot machen, `:Image paste`, fertig.
--- Das Bild landet als PNG neben dem Dokument (oder im konfigurierten
--- Unterverzeichnis), der Markdown-Link wird an der Cursorposition eingefügt.
---
--- Mit `paste.ask_alt_text = true` fragt `M.run` vor dem Einfügen nach einem
--- Alt-Text (über das UI-Kit aus lib.nvim, falls vorhanden). Default `false`,
--- damit der schnelle Fall — Screenshot, ein Tastendruck, fertig — nicht
--- durch eine Eingabeaufforderung unterbrochen wird, die die meisten
--- Aufrufe nicht brauchen.
---
--- Plattformen:
--- * Windows — `powershell.exe -STA` mit `System.Windows.Forms.Clipboard`.
---   Das `-STA` ist zwingend: die Zwischenablage-API verlangt einen
---   Single-Threaded-Apartment-Thread, sonst kommt immer `null` zurück.
---   Bewusst `powershell.exe` (5.1) statt `pwsh`, weil PowerShell 7 kein `-STA`
---   kennt und WinForms dort nicht zuverlässig verfügbar ist.
--- * Linux — `wl-paste` (Wayland), sonst `xclip` (X11).
--- * macOS — `pngpaste`, falls installiert.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Optionales UI-Kit aus lib.nvim. Fehlt es, fallen die Aufrufer auf die
--- Neovim-Bordmittel zurück — das Kit ist Komfort, keine Voraussetzung.
---@return table|nil
local function kit()
  local ok, k = pcall(require, "lib.nvim.ui.kit")
  return ok and k or nil
end

--- Zwischenablage-Bild nach `out` schreiben. Async wie `images.screenshot`s
--- `capture`, damit beide demselben Aufruf-Vertrag folgen und
--- `capture_with_optional_name` nicht zwischen sync/async unterscheiden muss
--- — der Lesevorgang selbst ist aber ein einzelner, schneller Prozessaufruf
--- (Millisekunden), kein mehrsekündiger interaktiver Vorgang wie bei einer
--- Bildschirmauswahl; ein `:wait()` wäre hier unschädlich, die einheitliche
--- Signatur ist trotzdem sauberer als eine Sonderregel für diesen einen Fall.
---@param out string Zielpfad (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function clipboard_to_file(out, callback)
  local cmd ---@type string[]

  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    local ps = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;",
      "$img = [System.Windows.Forms.Clipboard]::GetImage();",
      "if ($img -eq $null) { exit 3 };",
      ("$img.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png);"):format(out:gsub("'", "''")),
    }, " ")
    cmd = { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", ps }
  elseif vim.fn.has("mac") == 1 then
    if vim.fn.executable("pngpaste") == 0 then
      callback(false, "`pngpaste` nicht gefunden (brew install pngpaste)")
      return
    end
    cmd = { "pngpaste", out }
  else
    if vim.fn.executable("wl-paste") == 1 then
      cmd = { "sh", "-c", ("wl-paste --type image/png > '%s'"):format(out) }
    elseif vim.fn.executable("xclip") == 1 then
      cmd = { "sh", "-c", ("xclip -selection clipboard -t image/png -o > '%s'"):format(out) }
    else
      callback(false, "Weder `wl-paste` noch `xclip` gefunden")
      return
    end
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 3 then
        callback(false, "Kein Bild in der Zwischenablage")
        return
      end
      if result.code ~= 0 then
        callback(
          false,
          ("Zwischenablage konnte nicht gelesen werden (exit %d): %s"):format(result.code, vim.trim(result.stderr or ""))
        )
        return
      end

      local stat = vim.uv.fs_stat(out)
      if not stat or stat.size == 0 then
        pcall(vim.uv.fs_unlink, out)
        callback(false, "Kein Bild in der Zwischenablage")
        return
      end
      callback(true)
    end)
  end)
end

--- Vorgeschlagener Dateiname nach dem Template — Vorbelegung für die
--- Namensabfrage und Fallback, wenn keine eigene Eingabe kommt.
---@param buf integer
---@return string|nil suggestion nil, falls der Buffer keinen Dateinamen hat
local function default_filename(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  local doc_stem = vim.fn.fnamemodify(name, ":t:r")
  return cfg().paste.name_template:format(doc_stem, os.time())
end

--- User-Eingabe zu einem sicheren Dateinamen machen.
---
--- Nur der Dateiname selbst zählt: ein eingegebener Pfadanteil (Verzeichnisse,
--- `..`) wird über `:t` verworfen statt respektiert — sonst könnte eine
--- Eingabe wie `../../x` außerhalb von `paste.dir` schreiben. Die Endung wird
--- immer auf `.png` erzwungen, weil `clipboard_to_file` unabhängig vom Namen
--- immer PNG-Bytes schreibt; eine andere Endung wäre nur falsch beschriftet.
---@param input string Roher User-Input
---@return string|nil bereinigter Dateiname mit `.png`, oder nil ohne brauchbaren Rest
local function sanitize_filename(input)
  local base = vim.fn.fnamemodify(vim.trim(input or ""), ":t")
  local stem = vim.trim(vim.fn.fnamemodify(base, ":r"))
  if stem == "" or stem == "." or stem == ".." then return nil end
  return stem .. ".png"
end
-- Für Tests exponiert: reine Funktion, kein Terminal/Dateisystem nötig.
M.sanitize_filename = sanitize_filename

--- Zielpfad für ein neues Bild bestimmen und das Verzeichnis anlegen.
---@param buf integer
---@param filename_override string|nil bereits sanitisierter Name; nil = Template
---@return string|nil absoluter Pfad
---@return string|nil relativer Pfad für den Link
---@return string|nil err
local function target_paths(buf, filename_override)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil, nil, "Buffer hat keinen Dateinamen — bitte zuerst speichern" end

  local c = cfg().paste
  local doc_dir = vim.fn.fnamemodify(name, ":p:h")
  local doc_stem = vim.fn.fnamemodify(name, ":t:r")

  local sub = c.dir or ""
  local dir = (sub ~= "") and (doc_dir .. "/" .. sub) or doc_dir
  if vim.fn.isdirectory(dir) == 0 then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok then return nil, nil, "Verzeichnis konnte nicht angelegt werden: " .. dir end
  end

  local file = filename_override or c.name_template:format(doc_stem, os.time())
  local abs = dir .. "/" .. file
  local rel = (sub ~= "") and (sub .. "/" .. file) or file
  return abs, rel, nil
end

--- Link an der zum Zeitpunkt des Aufrufs gültigen Cursorposition einfügen.
--- Läuft nach dem Clipboard-Schreiben — synchron direkt danach, oder
--- asynchron nach der Alt-Text-Abfrage — und prüft deshalb den Buffer-Zustand
--- erneut: zwischen dem Ermitteln des Buffers und hier lag mindestens ein
--- synchroner Prozessaufruf, bei der Alt-Text-Abfrage zusätzlich eine
--- User-Eingabe. Der Buffer kann in der Zwischenzeit geschlossen oder auf
--- `nomodifiable` gesetzt worden sein — das Bild ist dann trotzdem
--- geschrieben, nur der Link fehlt, und das soll der User erfahren.
---@param buf integer
---@param rel string Pfad relativ zum Dokument
---@param alt string|nil Alt-Text; leer oder nil = kein Alt-Text
---@return nil
local function insert_link(buf, rel, alt)
  if not vim.api.nvim_buf_is_valid(buf) then
    notify().warn("Buffer nicht mehr vorhanden — Bild liegt unter " .. rel)
    return
  end
  if not vim.bo[buf].modifiable then
    notify().warn("Buffer nicht änderbar — Bild liegt unter " .. rel)
    return
  end

  -- Backslashes im Link vermeiden: Markdown-Pfade sind portabler mit `/`.
  local forward = (rel:gsub("\\", "/"))
  local c = cfg().paste
  local link = (alt and alt ~= "") and c.alt_link_template:format(alt, forward) or c.link_template:format(forward)

  local pos = vim.api.nvim_win_get_cursor(0)
  local inserted = pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { link })
  if not inserted then
    notify().warn("Link konnte nicht eingefügt werden — Bild liegt unter " .. rel)
    return
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { pos[1], pos[2] + #link })

  notify().info("Bild gespeichert: " .. rel)
end

--- Zweiter Teil von `M.run`/`M.screenshot`, nach einer optionalen
--- Namensabfrage: Bilddatei über `capture(abs, cb)` erzeugen und danach
--- optional nach Alt-Text fragen. `capture` ist austauschbar —
--- `clipboard_to_file` für `:Image paste`, `images.screenshot.capture` für
--- `:Image screenshot` — alles danach (Zielpfad, Link, Alt-Text) ist für
--- beide identisch. Async, weil eine interaktive Bildschirmauswahl
--- Sekunden bis zu einer Minute dauern kann und ein blockierendes Warten
--- darauf Neovim für diese ganze Zeit einfrieren würde.
---@param buf integer
---@param filename_override string|nil bereits sanitisiert; nil = Template
---@param capture fun(out: string, cb: fun(ok: boolean, err: string|nil))
---@return nil
local function paste_with_name(buf, filename_override, capture)
  local abs, rel, err = target_paths(buf, filename_override)
  if not abs or not rel then
    notify().error(err or "Zielpfad unbestimmbar")
    return
  end

  capture(abs, function(ok, cap_err)
    if not ok then
      notify().warn(cap_err or "Einfügen fehlgeschlagen")
      return
    end

    if not cfg().paste.ask_alt_text then
      insert_link(buf, rel, nil)
      return
    end

    local k = kit()
    if k and k.input then
      k.input({
        title = "Alt-Text (leer = ohne)",
        on_submit = function(alt)
          insert_link(buf, rel, alt)
        end,
        -- Abbrechen soll den Link trotzdem setzen, nur ohne Alt-Text — das
        -- Bild liegt an dieser Stelle bereits auf der Platte, ein verlorener
        -- Link (kit.input ruft ohne on_cancel bei <Esc> gar nichts auf) wäre
        -- die schlechtere Überraschung als ein Link ohne Alt-Text.
        on_cancel = function()
          insert_link(buf, rel, nil)
        end,
      })
    else
      local alt = vim.fn.input("Alt-Text (leer = ohne): ")
      insert_link(buf, rel, alt)
    end
  end)
end

--- Optional nach einem Dateinamen fragen, dann `paste_with_name` mit
--- `capture` als Aufnahmefunktion ausführen. Gemeinsamer Kern von `M.run`
--- (Zwischenablage) und `M.screenshot` (interaktive Bildschirmauswahl) —
--- beide unterscheiden sich nur darin, WIE die Bilddatei entsteht.
---@param capture fun(out: string, cb: fun(ok: boolean, err: string|nil))
---@return nil
local function capture_with_optional_name(capture)
  local buf = vim.api.nvim_get_current_buf()

  if not cfg().paste.ask_filename then
    paste_with_name(buf, nil, capture)
    return
  end

  local suggested = default_filename(buf)
  local k = kit()
  if k and k.input then
    k.input({
      title = "Dateiname",
      default = suggested,
      on_submit = function(name)
        paste_with_name(buf, sanitize_filename(name), capture)
      end,
      -- Anders als bei der Alt-Text-Abfrage: hier wurde noch nichts
      -- aufgenommen oder geschrieben — Abbrechen heißt also tatsächlich
      -- "nichts tun", nicht "mit Standardwerten weitermachen".
      on_cancel = function()
        notify().info("Abgebrochen")
      end,
    })
  else
    local name = vim.fn.input("Dateiname: ", suggested or "")
    if name == "" then
      notify().info("Abgebrochen")
      return
    end
    paste_with_name(buf, sanitize_filename(name), capture)
  end
end

--- Bild aus der Zwischenablage speichern und den Link an der Cursorposition
--- einfügen.
---@return nil
function M.run()
  capture_with_optional_name(clipboard_to_file)
end

--- Interaktive Bildschirm-Auswahl direkt in eine Datei aufnehmen und wie
--- `M.run` weiterverarbeiten — der Alltagsfall in einem Schritt statt drei
--- (Screenshot-Tool von Hand starten, Zwischenablage, `:Image paste`).
---@return nil
function M.screenshot()
  local screenshot = require("images.screenshot")
  if not screenshot.available() then
    notify().error(screenshot.unavailable_reason())
    return
  end
  capture_with_optional_name(screenshot.capture)
end

--- Bestehendes Bild durch den Zwischenablage-Inhalt ersetzen, ohne den Link
--- zu ändern. Nützlich, um einen veralteten Screenshot in-place zu
--- aktualisieren, statt Datei und Link neu anzulegen.
---@param path string|nil nil = Bild unter dem Cursor
---@return nil
function M.replace(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("Kein Bild unter dem Cursor oder am angegebenen Pfad")
    return
  end

  clipboard_to_file(file, function(ok, err)
    if not ok then
      notify().warn(err or "Ersetzen fehlgeschlagen")
      return
    end
    notify().info("Ersetzt: " .. vim.fn.fnamemodify(file, ":~"))
  end)
end

return M
