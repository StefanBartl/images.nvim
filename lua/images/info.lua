---@module 'images.info'
---@brief Determine an image file's metadata.
---@description
--- Format and dimensions come from ImageMagick, when it is present. Without
--- ImageMagick, size and modification time remain — the feature does not
--- become useless, which is why `magick` is deliberately optional.

local M = {}

---@internal
--- Result cache, keyed by path plus modification time plus size.
---
--- `magick identify` runs through `vim.system(...):wait()` and therefore
--- blocks the UI thread. Going async is not straightforward here: all six
--- callers (`ascii`, `compare` — twice per comparison —, `init`, `redact`,
--- `zen`) need the dimensions immediately for their layout arithmetic, so the
--- return value is part of the contract. What is possible: not asking about
--- the same file over and over. Format and dimensions only change when the
--- file changes — and that is exactly what the key captures. `:Image compare`
--- saves half its calls that way, and any repeated display of the same image
--- saves all of them.
---@type table<string, Images.Info>
local cache = {}

---@class Images.Info
---@field path string absolute path
---@field bytes integer file size
---@field mtime integer modification time (Unix)
---@field format string|nil e.g. "PNG"
---@field width integer|nil pixels
---@field height integer|nil pixels

--- Format bytes for humans.
---@param bytes integer
---@return string
function M.human_size(bytes)
  local units = { "B", "KB", "MB", "GB" }
  local value, unit = bytes, 1
  while value >= 1024 and unit < #units do
    value = value / 1024
    unit = unit + 1
  end
  if unit == 1 then return ("%d %s"):format(value, units[unit]) end
  return ("%.1f %s"):format(value, units[unit])
end

--- Collect metadata.
---@param path string absolute path
---@return Images.Info|nil
---@return string|nil err
function M.collect(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "file not found: " .. path end

  local mtime = stat.mtime and stat.mtime.sec or 0
  local key = ("%s:%d:%d"):format(path, mtime, stat.size)
  local hit = cache[key]
  if hit then return hit end

  ---@type Images.Info
  local info = {
    path = path,
    bytes = stat.size,
    mtime = mtime,
  }

  if require("lib.nvim.cross.executable").exists("magick") then
    -- `identify` as a subcommand of `magick`, not as its own binary: on
    -- Windows `convert.exe`/`identify.exe` collide with the system programs of
    -- the same name in System32.
    local res = vim.system({ "magick", "identify", "-format", "%m %w %h", path .. "[0]" }, { text = true }):wait()
    if res.code == 0 and res.stdout then
      local fmt, w, h = res.stdout:match("^(%S+)%s+(%d+)%s+(%d+)")
      info.format = fmt
      info.width = tonumber(w)
      info.height = tonumber(h)
    end
  end

  cache[key] = info
  return info
end

--- Metadata as lines, ready to display.
---@param info Images.Info
---@return string[]
function M.lines(info)
  local out = {
    "Path:     " .. vim.fn.fnamemodify(info.path, ":~"),
    "Size:     " .. M.human_size(info.bytes),
  }
  if info.width and info.height then
    table.insert(out, 2, ("Format:   %s %dx%d"):format(info.format or "?", info.width, info.height))
  elseif not require("lib.nvim.cross.executable").exists("magick") then
    out[#out + 1] = "Format:   (ImageMagick not installed)"
  end
  if info.mtime > 0 then out[#out + 1] = "Modified: " .. os.date("%Y-%m-%d %H:%M", info.mtime) end
  return out
end

return M
