---@module 'images'
---@brief Einstiegspunkt für images.nvim — `:Image` und die öffentliche Lua-API.
---@description
--- Bilder im Terminal anzeigen, ohne dass Neovim das Terminal verlässt.
---
--- Der Unterschied zu snacks.image und image.nvim: beide sprechen ausschließlich
--- das Kitty-Graphics-Protokoll. Auf nativem Windows-Neovim in WezTerm wird das
--- aus Neovim heraus nie gezeichnet — dieses Plugin nutzt stattdessen das
--- iTerm2-Protokoll (OSC 1337), das dort zuverlässig funktioniert.
---@see images.terminal für die Protokoll-Details und die Fallstricke
---@see images.paste für den Zwischenablage-Workflow

local M = {}

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Autocmds registrieren, die ein angezeigtes Bild wieder entfernen.
---@return nil
local function arm_clear()
  local events = require("images.config").get().display.clear_events
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

--- Eine Bilddatei anzeigen.
---@param path string Absoluter oder relativer Pfad
---@return boolean ok
function M.show(path)
  local terminal = require("images.terminal")
  if not terminal.available() then
    notify().error("Terminalausgabe nicht verfügbar (nvim_ui_send fehlt, benötigt API-Level 14)")
    return false
  end

  local file = require("images.resolve").to_path(path)
  if not file then
    notify().error("Bild nicht gefunden: " .. path)
    return false
  end

  local display = require("images.config").get().display
  -- Unter der Cursorzeile zeichnen, aber so weit oben, dass das Bild noch
  -- vollständig auf den Schirm passt.
  local row = math.min(vim.fn.screenrow() + 1, math.max(1, vim.o.lines - display.max_rows - 1))

  local ok, err = terminal.draw(file, row, 1, display.max_cols, display.max_rows)
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

--- Alle Bilder des Buffers auflisten und eines zur Anzeige auswählen.
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

  local items = {}
  for _, t in ipairs(found) do
    items[#items + 1] = t
  end

  vim.ui.select(items, {
    prompt = "Bild anzeigen",
    ---@param item ImagesNvim.Target
    format_item = function(item)
      return ("%4d  %s"):format(item.lnum, item.raw)
    end,
  }, function(choice)
    if choice then
      M.show(choice.path)
    end
  end)
end

--- Bild aus der Zwischenablage speichern und verlinken.
---@return nil
function M.paste()
  require("images.paste").run()
end

--- Ein angezeigtes Bild entfernen.
---@return nil
function M.clear()
  require("images.terminal").clear()
end

--- Plugin einrichten.
---@param opts table|nil siehe `images.config.DEFAULTS`
---@return nil
function M.setup(opts)
  local cfg = require("images.config").setup(opts)
  require("images.bindings.usrcmds").register(cfg)
  require("images.bindings.keymaps").register(cfg)
  require("images.bindings.autocmds").register(cfg)
end

return M
