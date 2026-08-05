---@module 'images.bindings.which_key'
--- Optional, guarded which-key group label for the `<leader>i` prefix.
--- which-key is a **soft** dependency: if it is not installed this is a
--- no-op. When present, registers a single group label so images.nvim's
--- `<leader>i*` keymaps (show, gallery, next, prev, paste) show up under a
--- named "images" group instead of a bare prefix. Individual key
--- descriptions already come from each mapping's `desc`, so nothing else
--- needs registering. Supports both the which-key v3 (`add`) and v2
--- (`register`) APIs.
---
--- Same pattern as buffer-ctx.nvim's `bindings/which_key.lua` — copied
--- rather than reinvented.

local M = {}

---Register the group with which-key, if available.
---@param prefix string e.g. "<leader>i"
---@return boolean registered
function M.setup(prefix)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end
  if type(wk.add) == "function" then
    -- which-key v3
    wk.add({ { prefix, group = "images: view images" } })
    return true
  elseif type(wk.register) == "function" then
    -- which-key v2
    wk.register({ [prefix] = { name = "+images: view images" } }, { mode = "n" })
    return true
  end
  return false
end

---Whether which-key is installed (for :checkhealth reporting).
---@return boolean
function M.available()
  local ok, wk = pcall(require, "which-key")
  return ok and type(wk) == "table"
end

return M
