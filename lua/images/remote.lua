---@module 'images.remote'
---@brief Download and cache an image from an http(s) URL.
---@description
--- Off by default: otherwise a markdown document containing a remote image
--- link would fire an outbound network request on a mere hover — exactly the
--- behaviour mail clients have blocked by default for years on privacy grounds
--- ("load external images"). `display.remote.enabled = true` turns it on
--- deliberately.
---
--- Applies only when explicitly displaying a single image (`:Image show`,
--- hover), not while scanning (`:Image list`/`gallery`/`next`/`prev`/
--- `orphans`, `images.resolve.to_path`) — otherwise merely listing a buffer's
--- images would fire N network requests just to show a list. `:Image
--- gallery`/`compare`/`browse`/`zen` do not support remote images (yet) for
--- the same reason — open work, see docs/ROADMAP/FEATURES.md.

local M = {}

--- Whether `target` looks like a downloadable remote URL. Deliberately http(s)
--- only — other schemes (`ftp://`, `file://`, …) would need different tools and
--- are not the practical case for markdown image links.
---@param target string
---@return boolean
function M.is_remote(target)
  return target:match("^https?://") ~= nil
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/remote"
  require("lib.nvim.fs.mkdirp")(dir)
  return dir
end

--- Cache path for a URL: a hash of the URL, with the extension taken from the
--- path component (without query/fragment) where recognisable. WezTerm detects
--- the image format from the bytes anyway; the extension is needed only so
--- that a `.svg` URL is still recognised as SVG after download and converted
--- (see `images.convert` and `images.terminal`'s draw path).
---@param url string
---@return string
local function cache_path(url)
  local key = vim.fn.sha256(url)
  local path_part = url:gsub("[?#].*$", "")
  local ext = path_part:match("%.([%w]+)$")
  return cache_dir() .. "/" .. key .. (ext and ("." .. ext:lower()) or "")
end

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Download the image at `url`, cached — a second call with the same URL does
--- not download again but hits the cache.
---
--- Asynchronous: the result arrives exclusively via `on_done`. The download
--- used to run through `vim.system(...):wait()` and held the UI thread for the
--- entire transfer — on a slow line, up to the configured timeout (default
--- 10s). A cache hit calls `on_done` within the same tick, with no process at
--- all.
---@param url string
---@param on_done fun(local_path: string|nil, err: string|nil)
---@return nil
function M.fetch(url, on_done)
  local c = cfg().display.remote
  if not c.enabled then return on_done(nil, "remote images are disabled (`display.remote.enabled = true` to turn them on)") end

  local out = cache_path(url)
  if vim.uv.fs_stat(out) then return on_done(out, nil) end

  local timeout_s = math.max(1, math.floor((c.timeout_ms or 10000) / 1000))
  local max_bytes = c.max_bytes or (20 * 1024 * 1024)

  local executable = require("lib.nvim.cross.executable")
  local cmd
  if executable.exists("curl") then
    cmd = {
      "curl",
      "-fsSL",
      "--max-time",
      tostring(timeout_s),
      "--max-filesize",
      tostring(max_bytes),
      "-o",
      out,
      url,
    }
  elseif executable.exists("wget") then
    -- -Q<bytes>: a quota, the closest equivalent to curl's --max-filesize.
    cmd = { "wget", "-q", "--timeout=" .. tostring(timeout_s), "-Q" .. tostring(max_bytes), "-O", out, url }
  else
    return on_done(nil, "neither `curl` nor `wget` found")
  end

  vim.system(cmd, { text = true }, function(result)
    -- vim.system callbacks run outside the main loop; the caller draws to the
    -- terminal and notifies afterwards.
    vim.schedule(function()
      if result.code ~= 0 then
        pcall(vim.uv.fs_unlink, out)
        on_done(nil, ("download failed (exit %d): %s"):format(result.code, vim.trim(result.stderr or "")))
        return
      end

      local stat = vim.uv.fs_stat(out)
      if not stat or stat.size == 0 then
        pcall(vim.uv.fs_unlink, out)
        on_done(nil, "download produced no file")
        return
      end

      on_done(out, nil)
    end)
  end)
end

return M
