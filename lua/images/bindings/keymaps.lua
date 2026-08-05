---@module 'images.bindings.keymaps'
---@brief Keymaps für images.nvim — alle abschaltbar, alle which-key-fähig.

local M = {}

--- Beschreibung der Bindungen für which-key und `docs/BINDINGS.md`.
---@type { lhs_key: string, desc: string, scope: string }[]
M.spec = {
  { lhs_key = "show", desc = "images: Bild unter dem Cursor anzeigen", scope = "buffer" },
}

--- Doppelklick auf einen Markdown-Link zeigt das Bild.
--- `<2-LeftMouse>` feuert nach dem regulären Klick, der Cursor steht also
--- bereits im Link — deshalb genügt `hover()` ohne eigene Positionsauswertung.
---@param buf integer
---@return nil
local function map_double_click(buf)
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local ok = require("images").hover()
    if not ok then
      -- Kein Bildlink getroffen: Doppelklick soll sich normal verhalten
      -- (Wortauswahl), statt stumm geschluckt zu werden.
      vim.cmd("normal! viw")
    end
  end, { buffer = buf, desc = "images: Bild bei Doppelklick auf Link" })
end

--- Keymaps registrieren.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  local keys = cfg.keymaps or {}
  if keys.show == false and not keys.double_click then
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("images.keymaps", { clear = true }),
    pattern = keys.filetypes or { "markdown" },
    ---@param ev { buf: integer }
    callback = function(ev)
      if type(keys.show) == "string" and keys.show ~= "" then
        vim.keymap.set("n", keys.show, function()
          require("images").hover()
        end, { buffer = ev.buf, desc = "images: Bild unter dem Cursor anzeigen" })
      end
      if keys.double_click then
        map_double_click(ev.buf)
      end
    end,
  })
end

return M
