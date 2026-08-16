---@module 'images.screenshot'
---@brief Interaktive Bildschirmauswahl direkt in eine Datei aufnehmen.
---@description
--- Ersetzt für den Alltagsfall drei Schritte (Screenshot-Tool von Hand
--- starten → Zwischenablage → `:Image paste`) durch einen: `:Image
--- screenshot` startet die Auswahl und läuft danach wie `:Image paste`
--- weiter (siehe `images.paste`s `capture_with_optional_name`).
---
--- Durchgehend asynchron (`vim.system` ohne `:wait()`, jede Fortsetzung in
--- `vim.schedule`), nie ein blockierendes `sleep`: Der User braucht für eine
--- Auswahl Sekunden bis zu einer Minute, und `:wait()` blockiert Neovims
--- gesamte Event-Loop für die Dauer des Subprozesses — ein eingefrorenes
--- Neovim, während man eigentlich nur einen Bereich zieht. Derselbe Aufbau
--- wie `lib.nvim.system.job`, das aus genau diesem Grund nie `:wait()`
--- verwendet.
---
--- Plattformen, unterschiedlich zuverlässig:
---
--- * macOS — `screencapture -i`: interaktive Auswahl per Ziehen oder Klick
---   auf ein Fenster, schreibt direkt in die Zieldatei. Bricht der User mit
---   <Esc> ab, liefert `screencapture` trotzdem Exit-Code 0 — daran ist ein
---   Abbruch nicht zu erkennen, nur an der fehlenden/leeren Datei.
---
--- * Linux — `grim -g "$(slurp)"` (Wayland, beide Werkzeuge nötig) oder
---   `maim -s` (X11, ein Werkzeug reicht). `slurp` liefert die vom User
---   gezogene Region auf stdout; bricht der User ab, liefert es nichts, und
---   `grim` wird gar nicht erst aufgerufen.
---
--- * Windows — der unsicherste der drei Wege. Es gibt keinen dokumentierten
---   CLI-Aufruf, der das moderne Snipping-Tool direkt in eine Datei
---   schreiben lässt. `explorer.exe ms-screenclip:` startet die
---   Auswahl-Oberfläche (dasselbe wie Win+Shift+S), kehrt aber sofort zurück
---   und kopiert das Ergebnis nach Abschluss in die Zwischenablage — ohne
---   Signal, wann das passiert. Dieses Modul pollt die Zwischenablage
---   danach per Timer (nicht blockierend) auf ein *neues* Bild, mit
---   Timeout. Die Polling-/Vergleichslogik selbst wurde manuell gegen eine
---   künstlich zeitversetzt veränderte Zwischenablage verifiziert; ob
---   `ms-screenclip:` in jeder Windows-Version wie dokumentiert startet, war
---   in dieser Umgebung nicht simulierbar — `:Image paste` bleibt der
---   unveränderte, bewährte Zwei-Schritt-Weg, falls diese Automatisierung
---   einmal nicht greift.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Datei nach einer Aufnahme prüfen: existiert sie und ist sie nicht leer?
--- Gemeinsamer Abschluss für macOS/Linux, wo ein Abbruch (<Esc>) nicht am
--- Exit-Code erkennbar ist, nur an der fehlenden/leeren Datei.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function finish_from_file(out, callback)
  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    callback(false, "Abgebrochen")
    return
  end
  callback(true)
end

-- ── macOS ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_mac(out, callback)
  vim.system({ "screencapture", "-i", out }, { text = true }, function()
    vim.schedule(function()
      finish_from_file(out, callback)
    end)
  end)
end

-- ── Linux ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_linux(out, callback)
  local executable = require("lib.nvim.cross.executable")
  if executable.exists("grim") and executable.exists("slurp") then
    vim.system({ "slurp" }, { text = true }, function(sel)
      vim.schedule(function()
        if sel.code ~= 0 or vim.trim(sel.stdout or "") == "" then
          callback(false, "Abgebrochen")
          return
        end
        vim.system({ "grim", "-g", vim.trim(sel.stdout), out }, { text = true }, function(gr)
          vim.schedule(function()
            if gr.code ~= 0 then
              callback(false, "grim fehlgeschlagen: " .. vim.trim(gr.stderr or ""))
              return
            end
            finish_from_file(out, callback)
          end)
        end)
      end)
    end)
  elseif executable.exists("maim") then
    -- -s: interaktive Auswahl per Ziehen. Abbruch (<Esc>) liefert exit != 0.
    vim.system({ "maim", "-s", out }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(false, "Abgebrochen")
          return
        end
        finish_from_file(out, callback)
      end)
    end)
  else
    callback(false, "Weder `grim`+`slurp` (Wayland) noch `maim` (X11) gefunden")
  end
end

-- ── Windows ──────────────────────────────────────────────────────────────────

--- PowerShell-Fragment: aktuelles Zwischenablage-Bild als Base64 ausgeben,
--- oder nichts, wenn keins da ist. Wiederverwendet für Vorher-Snapshot und
--- jeden Poll-Tick.
local PS_READ_CLIPBOARD_B64 = table.concat({
  "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;",
  "$img = [System.Windows.Forms.Clipboard]::GetImage();",
  "if ($img -eq $null) { exit 0 };",
  "$ms = New-Object System.IO.MemoryStream;",
  "$img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png);",
  "[Convert]::ToBase64String($ms.ToArray());",
}, " ")

--- Aktuellen Zwischenablage-Bildinhalt lesen, asynchron.
---@param callback fun(data: string|nil)
---@return nil
local function read_clipboard_image_async(callback)
  vim.system(
    { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", PS_READ_CLIPBOARD_B64 },
    { text = true },
    function(result)
      vim.schedule(function()
        local out = vim.trim(result.stdout or "")
        if result.code ~= 0 or out == "" then
          callback(nil)
          return
        end
        local ok, decoded = pcall(vim.base64.decode, out)
        callback((ok and decoded ~= "") and decoded or nil)
      end)
    end
  )
end

--- Snip-Oberfläche starten, per Timer (nicht blockierend) auf ein *neues*
--- Zwischenablage-Bild warten, dann nach `out` schreiben.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_windows(out, callback)
  read_clipboard_image_async(function(baseline)
    vim.system({ "explorer.exe", "ms-screenclip:" }, { text = true }, function(launch)
      vim.schedule(function()
        if launch.code ~= 0 then
          callback(false, "Snipping Tool konnte nicht gestartet werden")
          return
        end

        local c = cfg().display.screenshot
        local timeout_ms = c.windows_timeout_ms or 60000
        local interval_ms = c.windows_poll_interval_ms or 600
        local elapsed = 0

        local timer = assert(vim.uv.new_timer())
        local function stop()
          if not timer:is_closing() then
            timer:stop()
            timer:close()
          end
        end

        timer:start(
          interval_ms,
          interval_ms,
          vim.schedule_wrap(function()
            elapsed = elapsed + interval_ms
            read_clipboard_image_async(function(current)
              if current and current ~= baseline then
                stop()
                local fd = io.open(out, "wb")
                if not fd then
                  callback(false, "Zieldatei nicht schreibbar: " .. out)
                  return
                end
                fd:write(current)
                fd:close()
                callback(true)
              elseif elapsed >= timeout_ms then
                stop()
                callback(false, "Zeitüberschreitung — keine neue Aufnahme in der Zwischenablage erkannt")
              end
            end)
          end)
        )
      end)
    end)
  end)
end

-- ── Öffentliche API ──────────────────────────────────────────────────────────

--- Ob auf dieser Plattform überhaupt ein Aufnahmeweg zur Verfügung steht.
---@return boolean
function M.available()
  local executable = require("lib.nvim.cross.executable")
  if require("lib.nvim.cross.platform.is_macos")() then
    return executable.exists("screencapture")
  elseif require("lib.nvim.cross.platform.is_windows")() then
    return true -- ms-screenclip: gehört zu Windows, kein separates Tool nötig
  else
    return (executable.exists("grim") and executable.exists("slurp")) or executable.exists("maim")
  end
end

--- Begründung, wenn `available()` false ist — für die Fehlermeldung.
---@return string
function M.unavailable_reason()
  if require("lib.nvim.cross.platform.is_macos")() then
    return "`screencapture` nicht gefunden (gehört normalerweise zu macOS)"
  end
  return "Weder `grim`+`slurp` (Wayland) noch `maim` (X11) gefunden"
end

--- Interaktive Bildschirmauswahl starten und nach `out` schreiben. Kehrt
--- sofort zurück; `callback(ok, err)` läuft, sobald der User fertig ist,
--- abgebrochen hat, oder (nur Windows) das Timeout erreicht wurde.
---@param out string Zielpfad (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
function M.capture(out, callback)
  if require("lib.nvim.cross.platform.is_macos")() then
    capture_mac(out, callback)
  elseif require("lib.nvim.cross.platform.is_windows")() then
    capture_windows(out, callback)
  else
    capture_linux(out, callback)
  end
end

return M
