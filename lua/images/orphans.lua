---@module 'images.orphans'
---@brief Find image files in the target directory that no link points to.
---@description
--- The counterpart to `images.scan`, which reports unresolvable links — here it
--- is the other way round: files nobody references any more. Only the
--- configured `paste.dir` is considered, not the whole tree: it is the one
--- directory images.nvim writes to itself, and an image anywhere else in the
--- project may well be unlinked for a good reason.

local M = {}

---@class Images.Orphan
---@field path string absolute path
---@field rel string path relative to the target directory

--- Determine the target directory the same way pasting does (document
--- directory + `paste.dir`). Normalised, so that path comparisons in `M.find`
--- do not fail on mixed `/`/`\` (see `images.resolve.normalize_path`).
---@param buf integer
---@return string|nil
local function target_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  local resolve = require("images.resolve")
  local doc_dir = resolve.normalize_path(vim.fn.fnamemodify(name, ":p:h"))
  local sub = require("images.config").get().paste.dir or ""
  return (sub ~= "") and (doc_dir .. "/" .. sub) or doc_dir
end

--- List image files in `dir`. Not recursive — the paste target is a flat
--- directory, not a tree.
---@param dir string already normalised (see `target_dir`)
---@return string[]
local function list_images(dir)
  local out = {}
  local resolve = require("images.resolve")
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if kind == "file" and resolve.is_image(name) then out[#out + 1] = dir .. "/" .. name end
  end
  return out
end

--- Find orphaned images: present in the target directory but referenced by no
--- link in the buffer.
---@param buf integer|nil default: current buffer
---@return Images.Orphan[]
function M.find(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local dir = target_dir(buf)
  if not dir or vim.fn.isdirectory(dir) == 0 then return {} end

  local referenced = {}
  for _, target in ipairs(require("images.scan").buffer(buf)) do
    referenced[target.path] = true
  end

  local orphans = {}
  for _, path in ipairs(list_images(dir)) do
    if not referenced[path] then orphans[#orphans + 1] = { path = path, rel = path:sub(#dir + 2) } end
  end
  table.sort(orphans, function(a, b)
    return a.rel < b.rel
  end)
  return orphans
end

return M
