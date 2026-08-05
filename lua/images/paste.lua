---@module 'images.paste'
---@brief Bild aus der Zwischenablage als Datei ablegen und den Link einfügen.
---@description
--- Der Alltagsfall für Dokumentation: Screenshot machen, `:Image paste`, fertig.
--- Das Bild landet als PNG neben dem Dokument (oder im konfigurierten
--- Unterverzeichnis), der Markdown-Link wird an der Cursorposition eingefügt.
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

--- Zwischenablage-Bild nach `out` schreiben.
---@param out string Zielpfad (PNG)
---@return boolean ok
---@return string|nil err
local function clipboard_to_file(out)
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
      return false, "`pngpaste` nicht gefunden (brew install pngpaste)"
    end
    cmd = { "pngpaste", out }
  else
    if vim.fn.executable("wl-paste") == 1 then
      cmd = { "sh", "-c", ("wl-paste --type image/png > '%s'"):format(out) }
    elseif vim.fn.executable("xclip") == 1 then
      cmd = { "sh", "-c", ("xclip -selection clipboard -t image/png -o > '%s'"):format(out) }
    else
      return false, "Weder `wl-paste` noch `xclip` gefunden"
    end
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code == 3 then
    return false, "Kein Bild in der Zwischenablage"
  end
  if result.code ~= 0 then
    return false, ("Zwischenablage konnte nicht gelesen werden (exit %d): %s")
      :format(result.code, vim.trim(result.stderr or ""))
  end

  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    return false, "Kein Bild in der Zwischenablage"
  end
  return true
end

--- Zielpfad für ein neues Bild bestimmen und das Verzeichnis anlegen.
---@param buf integer
---@return string|nil absoluter Pfad
---@return string|nil relativer Pfad für den Link
---@return string|nil err
local function target_paths(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil, nil, "Buffer hat keinen Dateinamen — bitte zuerst speichern"
  end

  local c = cfg().paste
  local doc_dir = vim.fn.fnamemodify(name, ":p:h")
  local doc_stem = vim.fn.fnamemodify(name, ":t:r")

  local sub = c.dir or ""
  local dir = (sub ~= "") and (doc_dir .. "/" .. sub) or doc_dir
  if vim.fn.isdirectory(dir) == 0 then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok then
      return nil, nil, "Verzeichnis konnte nicht angelegt werden: " .. dir
    end
  end

  local file = c.name_template:format(doc_stem, os.time())
  local abs = dir .. "/" .. file
  local rel = (sub ~= "") and (sub .. "/" .. file) or file
  return abs, rel, nil
end

--- Bild aus der Zwischenablage speichern und den Link an der Cursorposition
--- einfügen.
---@return nil
function M.run()
  local buf = vim.api.nvim_get_current_buf()

  local abs, rel, err = target_paths(buf)
  if not abs or not rel then
    notify().error(err or "Zielpfad unbestimmbar")
    return
  end

  local ok, cb_err = clipboard_to_file(abs)
  if not ok then
    notify().warn(cb_err or "Einfügen fehlgeschlagen")
    return
  end

  -- Zwischen dem Ermitteln des Buffers und hier lag ein synchroner
  -- Prozessaufruf. Der Buffer kann inzwischen geschlossen oder auf
  -- `nomodifiable` gesetzt worden sein — das Bild ist dann trotzdem
  -- geschrieben, nur der Link fehlt, und das soll der User erfahren.
  if not vim.api.nvim_buf_is_valid(buf) then
    notify().warn("Buffer nicht mehr vorhanden — Bild liegt unter " .. rel)
    return
  end
  if not vim.bo[buf].modifiable then
    notify().warn("Buffer nicht änderbar — Bild liegt unter " .. rel)
    return
  end

  -- Backslashes im Link vermeiden: Markdown-Pfade sind portabler mit `/`.
  local link = cfg().paste.link_template:format((rel:gsub("\\", "/")))
  local pos = vim.api.nvim_win_get_cursor(0)
  local inserted = pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { link })
  if not inserted then
    notify().warn("Link konnte nicht eingefügt werden — Bild liegt unter " .. rel)
    return
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { pos[1], pos[2] + #link })

  notify().info("Bild gespeichert: " .. rel)
end

return M
