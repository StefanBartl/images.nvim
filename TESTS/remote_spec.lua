-- TESTS/remote_spec.lua — remote image detection and the off-by-default state.
--
-- No real download in this test: `fetch` with the default
-- (`display.remote.enabled = false`) returns its error synchronously without
-- ever touching the network — precisely the case that must never fire a request
-- without consent.

---@param H table harness from TESTS/run.lua
return function(H)
  local remote = require("images.remote")
  local config = require("images.config")

  --- The same cache path `images.remote`'s own (private) `cache_path()`
  --- computes: a hash of the URL, plus the extension off the URL's path
  --- component. Duplicated here rather than exported — the test wants to
  --- prove the *public* contract (a URL round-trips through `fetch`), not
  --- reach into the module's internals.
  ---@param url string
  ---@return string
  local function expected_cache_path(url)
    local dir = vim.fn.stdpath("cache") .. "/images.nvim/remote"
    vim.fn.mkdir(dir, "p")
    local path_part = url:gsub("[?#].*$", "")
    local ext = path_part:match("%.([%w]+)$")
    return dir .. "/" .. vim.fn.sha256(url) .. (ext and ("." .. ext:lower()) or "")
  end

  -- ── is_remote: http(s) only ──────────────────────────────────────────────
  H.ok(remote.is_remote("https://example.com/image.png"), "https is recognised")
  H.ok(remote.is_remote("http://example.com/image.png"), "http is recognised")
  H.falsy(remote.is_remote("ftp://example.com/image.png"), "ftp is deliberately unsupported")
  H.falsy(remote.is_remote("/local/image.png"), "a local path is not remote")
  H.falsy(remote.is_remote("C:\\local\\image.png"), "a Windows path is not remote")
  H.falsy(remote.is_remote("relative/image.png"), "a relative path is not remote")

  -- ── fetch: off by default, no network access ─────────────────────────────
  require("images.config").setup(nil) -- defaults: remote.enabled = false
  local png, err
  remote.fetch("https://example.com/image.png", function(p, e)
    png, err = p, e
  end)
  H.falsy(png, "nothing is downloaded without consent")
  H.contains(err or "", "disabled", "…with a reason that points at the option")
  H.contains(err or "", "display.remote.enabled", "…naming the exact option")

  -- ── resolve.is_image recognises remote URLs with a discernible extension ─
  local resolve = require("images.resolve")
  H.ok(resolve.is_image("https://example.com/photo.jpg"), "an https URL with an extension counts as an image")
  H.ok(resolve.is_image("https://example.com/photo.png?v=2"), "…even with a query string after it")
  H.falsy(resolve.is_image("https://example.com/api/image"), "…but not without a discernible extension")

  -- ── resolve.to_path does not download remote URLs (images.remote's job) ──
  H.eq(
    resolve.to_path("https://example.com/photo.jpg"),
    nil,
    "to_path stays purely local; doing otherwise would be wrong here even with remote on"
  )

  -- ── the disk cache has a TTL (PERF-42), not "forever" ────────────────────
  -- Regression coverage for cd6099d: the cache-hit test used to be just
  -- `vim.uv.fs_stat(out)` truthy, with no notion of an entry going stale.
  -- Every case below is synchronous and process-free, the same discipline as
  -- the "off by default" test above — a stale-cache miss falls through to
  -- the curl/wget dispatch, which is exercised here via a monkey-patched
  -- `executable.exists` rather than a real process, so the test is neither
  -- network-dependent nor tool-dependent (curl/wget may be absent in CI).
  do
    local executable = require("lib.nvim.cross.executable")
    local real_exists = executable.exists
    local prev_conf = config.get()

    -- A fresh cache entry (mtime "now") is served without reaching the
    -- curl/wget dispatch at all -- the synchronous branch `fetch` takes on a
    -- hit, proven here by never having monkey-patched `exists` for this case.
    do
      config.setup({ display = { remote = { enabled = true } } })
      local url = "https://example.com/images-nvim-ttl-fresh.png"
      local out = expected_cache_path(url)
      local f = assert(io.open(out, "wb"))
      f:write("cached bytes")
      f:close()
      assert(vim.uv.fs_utime(out, os.time(), os.time()))

      local hit_path, hit_err
      remote.fetch(url, function(p, e)
        hit_path, hit_err = p, e
      end)
      H.eq(hit_path, out, "a fresh cache entry is served as-is")
      H.eq(hit_err, nil, "…with no error")
      pcall(os.remove, out)
    end

    -- An entry older than `cache_ttl_s` is *not* a hit: `fetch` must fall
    -- through to the download dispatch instead of serving it, which this
    -- proves by making that dispatch fail in a way only reachable past the
    -- TTL gate ("neither curl nor wget found", from a fully stubbed-out
    -- `exists`) rather than returning the (stale) cached path.
    do
      config.setup({ display = { remote = { enabled = true, cache_ttl_s = 1 } } })
      local url = "https://example.com/images-nvim-ttl-expired.png"
      local out = expected_cache_path(url)
      local f = assert(io.open(out, "wb"))
      f:write("stale bytes")
      f:close()
      assert(vim.uv.fs_utime(out, os.time() - 100000, os.time() - 100000))

      executable.exists = function()
        return false
      end
      local stale_path, stale_err
      remote.fetch(url, function(p, e)
        stale_path, stale_err = p, e
      end)
      executable.exists = real_exists

      H.falsy(stale_path, "an entry past its TTL is not served from the cache")
      H.contains(stale_err or "", "curl", "…and fetch actually re-attempted the download (reached the dispatch)")
      pcall(os.remove, out)
    end

    -- An invalid `cache_ttl_s` (ERR-22: not a number, or non-positive)
    -- degrades to the built-in default instead of e.g. treating 0 as "always
    -- stale" -- proven the same way: a fresh entry must still be a hit.
    for _, bad_ttl in ipairs({ 0, -5, "forever", false }) do
      config.setup({ display = { remote = { enabled = true, cache_ttl_s = bad_ttl } } })
      local url = "https://example.com/images-nvim-ttl-invalid-" .. tostring(bad_ttl) .. ".png"
      local out = expected_cache_path(url)
      local f = assert(io.open(out, "wb"))
      f:write("cached bytes")
      f:close()
      assert(vim.uv.fs_utime(out, os.time(), os.time()))

      local fallback_path, fallback_err
      remote.fetch(url, function(p, e)
        fallback_path, fallback_err = p, e
      end)
      H.eq(fallback_path, out, "cache_ttl_s = " .. tostring(bad_ttl) .. " falls back to the default, not a 0-second TTL")
      H.eq(fallback_err, nil, "…with no error")
      pcall(os.remove, out)
    end

    executable.exists = real_exists
    config.setup(prev_conf)
  end
end
