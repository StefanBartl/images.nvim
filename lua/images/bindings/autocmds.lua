---@module 'images.bindings.autocmds'
---@brief Autocmds for images.nvim.
---@description
--- The cleanup autocmds (remove the image on cursor movement) are deliberately
--- not registered here but only once an image is shown, and with `once` (see
--- `images.init`). Otherwise they would run permanently while being relevant
--- only for the few seconds an image is actually on screen.

local autocmd = require("lib.nvim.autocmd")

local M = {}

--- Register the autocmds.
---@param _cfg ImagesNvim.Config
---@return nil
function M.register(_cfg)
  autocmd.create("VimLeavePre", function()
    require("images.terminal").clear()
  end, {
    group = autocmd.group("images.autocmds", true),
    desc = "images: clear the displayed image before quitting",
  })
end

return M
