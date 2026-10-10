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
--- the same reason — open work.

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

--- A configured positive number, made safe to divide/format below (ERR-22):
--- `(c.timeout_ms or 10000) / 1000` throws for a non-number `timeout_ms`
--- (reproduced with a boolean, a string and a table — "attempt to perform
--- arithmetic on a ... value") since `or` only substitutes on `nil`/`false`,
--- not on a wrong type. `>= 1` also rejects 0/negative, which would divide
--- down to a `timeout_s` of 0 before `math.max(1, ...)` masks it, or pass a
--- negative/zero byte quota straight through to curl/wget.
---@param value any
---@param default number
---@return number
local function valid_positive(value, default)
  if type(value) == "number" and value == value and value >= 1 then return value end
  return default
end

--- The host part of an http(s) URL, lower-cased, without userinfo and port;
--- IPv6 literals come back without their brackets.
---@param url string
---@return string|nil
local function url_host(url)
  local authority = url:match("^https?://([^/?#]*)")
  if not authority then return nil end
  authority = authority:gsub("^.*@", "")
  local bracketed = authority:match("^%[([^%]]*)%]")
  local host = bracketed or authority:gsub(":%d*$", "")
  return host:lower()
end

--- Whether `url` points at this machine or a private network by its literal
--- host: `localhost`, loopback, RFC1918, link-local (cloud metadata lives at
--- 169.254.169.254), CGNAT, unique-local/link-local IPv6, and the numeric
--- spellings (`2130706433`, `0x7f.1`) curl would still resolve to those.
---
--- Literal hosts only: a DNS name that resolves to a private address, or a
--- redirect to one, is not caught -- that needs the resolver's answer, which
--- neither curl nor wget exposes before connecting.
---@param url string
---@return boolean
function M.is_private_host(url)
  local host = url_host(url)
  if not host or host == "" then return true end
  if host == "localhost" or host:match("%.localhost$") then return true end

  if host:find(":", 1, true) then -- IPv6 literal
    local v4 = host:match("^::ffff:(%d+%.%d+%.%d+%.%d+)$")
    if v4 then return M.is_private_host("http://" .. v4) end
    return host == "::" or host == "::1" or host:match("^fe[89ab]") ~= nil or host:match("^f[cd]") ~= nil
  end

  local a, b = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if a then
    a, b = tonumber(a), tonumber(b)
    return a == 0
      or a == 10
      or a == 127
      or (a == 169 and b == 254)
      or (a == 172 and b >= 16 and b <= 31)
      or (a == 192 and b == 168)
      or (a == 100 and b >= 64 and b <= 127)
  end

  -- Not a dotted quad but made of digits/hex/dots only: an obfuscated IPv4
  -- ("2130706433", "0x7f000001", "127.1") that curl still resolves.
  if host:match("^[%d%.]+$") or host:match("^0x%x*[%x%.x]*$") then return true end
  return false
end

--- The download command for `tool`.
---
--- Redirects are followed, but only within http(s) and at most 5 hops --
--- without `--proto-redir` a redirect may switch to another scheme (`file://`,
--- `ftp://`, `gopher://`).
---
--- curl's `--max-filesize` is only enforced when the server announces the size
--- up front; a chunked response is not cut off. wget's `-Q` quota never limits
--- a single file fetched with `-O`. Neither is therefore a real limit on its
--- own: `M.fetch` checks the size of what arrived and discards an oversized
--- file, and `--max-time` bounds how long a streaming response can keep
--- writing.
---@param tool "curl"|"wget"
---@param url string
---@param out string
---@param timeout_s integer
---@param max_bytes integer
---@return string[]
function M.build_cmd(tool, url, out, timeout_s, max_bytes)
  if tool == "curl" then
    return {
      "curl",
      "-fsSL",
      "--proto",
      "=http,https",
      "--proto-redir",
      "=http,https",
      "--max-redirs",
      "5",
      "--max-time",
      tostring(timeout_s),
      "--max-filesize",
      tostring(max_bytes),
      "-o",
      out,
      url,
    }
  end
  return { "wget", "-q", "--timeout=" .. tostring(timeout_s), "--max-redirect=5", "-O", out, url }
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
  -- PERF-42: a cache entry needs a defined invalidation, not "forever" --
  -- otherwise a URL whose content changes (an avatar, a status badge, a
  -- regenerated screenshot) is served stale for the life of the cache dir.
  local ttl_s = valid_positive(c.cache_ttl_s, 24 * 60 * 60)
  local cached_stat = vim.uv.fs_stat(out)
  if cached_stat and cached_stat.mtime and (os.time() - cached_stat.mtime.sec) < ttl_s then return on_done(out, nil) end

  local timeout_s = math.max(1, math.floor(valid_positive(c.timeout_ms, 10000) / 1000))
  local max_bytes = valid_positive(c.max_bytes, 20 * 1024 * 1024)

  if not c.allow_private_hosts and M.is_private_host(url) then
    return on_done(nil, "refusing to fetch a local/private address (`display.remote.allow_private_hosts = true` to allow)")
  end

  local executable = require("lib.nvim.cross.executable")
  local tool
  if executable.exists("curl") then
    tool = "curl"
  elseif executable.exists("wget") then
    tool = "wget"
  else
    return on_done(nil, "neither `curl` nor `wget` found")
  end
  local cmd = M.build_cmd(tool, url, out, timeout_s, max_bytes)

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

      if stat.size > max_bytes then
        pcall(vim.uv.fs_unlink, out)
        on_done(nil, ("download exceeds the %d byte limit (`display.remote.max_bytes`)"):format(max_bytes))
        return
      end

      on_done(out, nil)
    end)
  end)
end

return M
