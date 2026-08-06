---@module 'images.health'
---@brief `:checkhealth images`

local M = {}

---@return nil
local function check_output()
  if vim.api.nvim_ui_send then
    vim.health.ok("`nvim_ui_send` verfügbar — Bildausgabe möglich")
  else
    vim.health.error(
      "`nvim_ui_send` fehlt (benötigt API-Level 14)",
      { "Neovim aktualisieren — ohne diese API kann kein Bild gezeichnet werden" }
    )
  end
end

---@return nil
local function check_terminal()
  -- Dieselbe Prüfung, die auch vor dem Zeichnen läuft — eine zweite Heuristik
  -- hier würde nur auseinanderlaufen.
  local cap = require("images.terminal").capability(false)

  if cap.ok and cap.terminal then
    vim.health.ok(("`%s` erkannt — OSC 1337 wird unterstützt"):format(cap.terminal))
  elseif cap.ok then
    vim.health.warn("Unterstützung wird angenommen (`display.assume_supported`)")
  else
    vim.health.warn(cap.reason or "Terminal nicht erkannt", {
      cap.hint or "",
      "images.nvim braucht ein Terminal mit iTerm2-Protokoll (OSC 1337).",
    })
  end

  if cap.hint and cap.ok then vim.health.warn(cap.hint) end
end

---@return nil
local function check_clipboard()
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    if vim.fn.executable("powershell.exe") == 1 then
      vim.health.ok("`powershell.exe` gefunden — `:Image paste` verfügbar")
    else
      vim.health.warn("`powershell.exe` nicht gefunden — `:Image paste` funktioniert nicht")
    end
    return
  end

  if vim.fn.has("mac") == 1 then
    if vim.fn.executable("pngpaste") == 1 then
      vim.health.ok("`pngpaste` gefunden — `:Image paste` verfügbar")
    else
      vim.health.warn("`pngpaste` fehlt", { "brew install pngpaste" })
    end
    return
  end

  if vim.fn.executable("wl-paste") == 1 then
    vim.health.ok("`wl-paste` gefunden — `:Image paste` verfügbar")
  elseif vim.fn.executable("xclip") == 1 then
    vim.health.ok("`xclip` gefunden — `:Image paste` verfügbar")
  else
    vim.health.warn("Weder `wl-paste` noch `xclip` gefunden — `:Image paste` funktioniert nicht")
  end
end

---@return nil
local function check_screenshot()
  local screenshot = require("images.screenshot")
  if screenshot.available() then
    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
      vim.health.ok("Snipping Tool (`ms-screenclip:`) verfügbar — `:Image screenshot`")
    else
      vim.health.ok("`:Image screenshot` verfügbar")
    end
  else
    -- info statt warn: :Image paste bleibt der unveränderte Weg, ohne
    -- screenshot-fähige Werkzeuge geht nur der eine Zusatzbefehl nicht.
    vim.health.info(
      screenshot.unavailable_reason() .. " — `:Image screenshot` bleibt aus, `:Image paste` funktioniert weiterhin"
    )
  end
end

---@return nil
local function check_imagemagick()
  if vim.fn.executable("magick") == 1 then
    vim.health.ok(
      "`magick` gefunden — `:Image info`-Abmessungen, `:Image compare`s relative Skalierung und SVG-Anzeige verfügbar"
    )
  else
    -- Kein `vim.health.warn`: ImageMagick verbessert diese drei Features,
    -- ist aber für alles andere keine Voraussetzung (siehe Leitplanke in
    -- docs/ROADMAP/README.md) — `info` fehlen dann nur die Abmessungen,
    -- `compare` zeigt beide Bilder gleich groß, und SVGs melden beim
    -- Zeichnen einen klaren Fehler statt eines stillen Fehlschlags.
    vim.health.info(
      "`magick` nicht gefunden — `:Image info`-Abmessungen, `:Image compare`s relative Skalierung und SVG-Anzeige bleiben aus, alles andere funktioniert"
    )
  end
end

---@return nil
local function check_deps()
  if pcall(require, "lib.nvim.usercmd.composer") then
    vim.health.ok("`lib.nvim` gefunden")
  else
    vim.health.error("`lib.nvim` fehlt", { "StefanBartl/lib.nvim als Dependency eintragen" })
  end

  if pcall(require, "markdown.util.path") then
    vim.health.ok("`markdown.nvim` gefunden — dessen Pfad-Resolver wird genutzt")
  else
    vim.health.info("`markdown.nvim` nicht vorhanden — interne Pfadauflösung wird genutzt")
  end
end

---@return nil
function M.check()
  vim.health.start("images.nvim")
  check_output()
  check_terminal()
  check_clipboard()
  check_screenshot()
  check_imagemagick()
  check_deps()
end

return M
