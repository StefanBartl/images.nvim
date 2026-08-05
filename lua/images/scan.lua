---@module 'images.scan'
---@brief Alle Bildlinks eines Buffers einsammeln.

local M = {}

--- Bildziele eines Buffers, optional auf einen Zeilenbereich beschränkt.
---@param buf integer|nil default: aktueller Buffer
---@param first integer|nil 1-basierte Startzeile
---@param last integer|nil 1-basierte Endzeile
---@return ImagesNvim.Target[] gefundene Ziele
---@return string[] unauflösbare Ziele (für eine Warnung an den User)
function M.buffer(buf, first, last)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}, {}
  end
  local resolve = require("images.resolve")

  local from = (first and first > 0) and first - 1 or 0
  local to = last or -1
  local lines = vim.api.nvim_buf_get_lines(buf, from, to, false)

  local found, missing = {}, {}
  for i, line in ipairs(lines) do
    for _, link in ipairs(resolve.links_in_line(line)) do
      if resolve.is_image(link.target) then
        local path = resolve.to_path(link.target, buf)
        if path then
          found[#found + 1] = { raw = link.target, path = path, lnum = from + i }
        else
          missing[#missing + 1] = link.target
        end
      end
    end
  end
  return found, missing
end

return M
