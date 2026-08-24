---@module 'images.scan'
---@brief Collect every image link in a buffer.

local M = {}

--- A buffer's image targets, optionally restricted to a line range.
---@param buf integer|nil default: current buffer
---@param first integer|nil 1-based first line
---@param last integer|nil 1-based last line
---@return ImagesNvim.Target[] targets found
---@return string[] unresolvable targets (to warn the user about)
function M.buffer(buf, first, last)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return {}, {} end
  local resolve = require("images.resolve")

  local from = (first and first > 0) and first - 1 or 0
  local to = last or -1
  local lines = vim.api.nvim_buf_get_lines(buf, from, to, false)

  local found, missing = {}, {}
  for i, line in ipairs(lines) do
    for _, link in ipairs(resolve.links_in_line(line, from + i)) do
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
