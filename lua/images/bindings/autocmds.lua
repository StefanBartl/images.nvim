---@module 'images.bindings.autocmds'
---@brief Autocmds für images.nvim.
---@description
--- Die Aufräum-Autocmds (Bild bei Cursorbewegung entfernen) werden bewusst nicht
--- hier registriert, sondern erst beim Anzeigen eines Bildes und mit `once`
--- (siehe `images.init`). Sonst liefen sie permanent mit, obwohl sie nur für die
--- wenigen Sekunden relevant sind, in denen ein Bild auf dem Schirm steht.

local M = {}

--- Autocmds registrieren.
---@param _cfg ImagesNvim.Config
---@return nil
function M.register(_cfg)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("images.autocmds", { clear = true }),
    desc = "images: angezeigtes Bild vor dem Beenden entfernen",
    callback = function()
      require("images.terminal").clear()
    end,
  })
end

return M
