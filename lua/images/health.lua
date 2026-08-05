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
  local term = vim.env.TERM_PROGRAM or ""
  local wez = vim.env.WEZTERM_VERSION or vim.env.WEZTERM_EXECUTABLE or ""

  if wez ~= "" or term:lower():find("wezterm") then
    vim.health.ok("WezTerm erkannt — OSC 1337 wird unterstützt")
  elseif term:lower():find("iterm") then
    vim.health.ok("iTerm2 erkannt — OSC 1337 wird unterstützt")
  else
    vim.health.warn(
      "Terminal nicht sicher erkannt (TERM_PROGRAM=" .. (term ~= "" and term or "leer") .. ")",
      {
        "images.nvim braucht ein Terminal mit iTerm2-Protokoll (OSC 1337):",
        "WezTerm, iTerm2, oder ein anderes mit OSC-1337-Unterstützung.",
        "Test: `wezterm imgcat bild.png` bzw. das Äquivalent des Terminals.",
      }
    )
  end

  if vim.env.TMUX and vim.env.TMUX ~= "" then
    vim.health.warn("tmux erkannt", {
      "Bildsequenzen brauchen `set -g allow-passthrough on` in der tmux-Konfiguration",
    })
  end
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
  check_deps()
end

return M
