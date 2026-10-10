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

  -- ── private hosts are refused, public ones are not ──────────────────────
  for _, url in ipairs({
    "http://localhost/a.png",
    "http://localhost./a.png",
    "http://foo.localhost:8080/a.png",
    "http://127.0.0.1/a.png",
    "http://127.0.0.1./a.png",
    "http://user@10.1.2.3/a.png",
    "http://evil.example@127.0.0.1/a.png",
    "http://172.16.0.1/a.png",
    "http://172.31.255.1/a.png",
    "http://192.168.1.1/a.png",
    "http://169.254.169.254/latest/meta-data/",
    "http://100.64.0.1/a.png",
    "http://0.0.0.0/a.png",
    "http://[::1]/a.png",
    "http://[0:0:0:0:0:0:0:1]/a.png",
    "http://[fe80::1]/a.png",
    "http://[fd00::1]/a.png",
    "http://[::ffff:127.0.0.1]/a.png",
    "http://[::ffff:7f00:1]/a.png",
    "http://[64:ff9b::7f00:1]/a.png",
    "http://[2002:7f00:1::]/a.png",
    "http://[fe80::1%25eth0]/a.png",
    "http://2130706433/a.png",
    "http://0x7f000001/a.png",
    "http://0177.0.0.1/a.png",
    "http://127.1/a.png",
    "http://127.0.0.%31/a.png",
    "http://127.0.0.1\\@example.com/a.png",
    "http://intranet/a.png",
    "http://printer.local/a.png",
    "http://wiki.internal/a.png",
  }) do
    H.ok(remote.is_private_host(url), "private: " .. url)
  end
  for _, url in ipairs({
    "https://example.com/a.png",
    "https://example.com./a.png",
    "http://8.8.8.8/a.png",
    "http://1.1.1.1/a.png",
    "http://172.32.0.1/a.png",
    "http://172.15.0.1/a.png",
    "http://100.128.0.1/a.png",
    "http://[2606:4700:4700::1111]/a.png",
    "http://[2002:808:808::]/a.png",
    "https://localhost.example.com/a.png",
    "https://deadbeef.cafe/a.png",
    "https://user:pw@example.com:8443/a.png",
  }) do
    H.falsy(remote.is_private_host(url), "public: " .. url)
  end

  -- ── download argv: one hop, no redirects followed by the tool ────────────
  do
    local curl_cmd = remote.build_cmd("curl", "https://example.com/a.png", "/tmp/out.png", 10, 1234)
    local joined = " " .. table.concat(curl_cmd, " ") .. " "
    H.contains(joined, " --proto =http,https ", "curl restricts the protocols")
    H.contains(joined, " --max-filesize 1234 ", "…keeps the size limit")
    H.contains(joined, " --globoff ", "…and does not expand [] or {} in a URL into several requests")
    H.contains(joined, " -w ", "…reports status and redirect target for the caller")
    H.falsy(joined:find(" -L ", 1, true) or joined:find(" -fsSL ", 1, true), "…never follows redirects itself")
    H.eq(curl_cmd[#curl_cmd], "https://example.com/a.png", "…the URL stays one argv element, last")

    local wget_cmd = remote.build_cmd("wget", "https://example.com/a.png", "/tmp/out.png", 10, 1234)
    local wjoined = " " .. table.concat(wget_cmd, " ") .. " "
    H.contains(wjoined, " --max-redirect=0 ", "wget does not follow redirects itself either")
    H.contains(wjoined, " -S ", "…prints the response headers so the redirect target can be read")
    H.contains(wjoined, " --tries=1 ", "…and does not retry 20 times")
    H.falsy(wjoined:find(" -Q", 1, true), "…and no longer pretends -Q is a size limit")
    H.eq(wget_cmd[#wget_cmd], "https://example.com/a.png", "…the URL stays one argv element, last")
  end

  -- ── fetch: the redirect/DNS/size paths, with the tools stubbed out ───────
  do
    local executable = require("lib.nvim.cross.executable")
    local real_exists, real_system, real_getaddrinfo = executable.exists, vim.system, vim.uv.getaddrinfo

    local calls, resolver, behave
    local function install()
      calls = {}
      resolver = function()
        return { { addr = "93.184.216.34", family = "inet" } }
      end
      executable.exists = function(name)
        return name == "curl"
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.uv.getaddrinfo = function(host, _, _, cb)
        vim.schedule(function()
          cb(nil, resolver(host))
        end)
        return {}
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        local out
        for i, a in ipairs(cmd) do
          if a == "-o" then out = cmd[i + 1] end
        end
        calls[#calls + 1] = { url = cmd[#cmd], out = out, cmd = cmd }
        return behave(#calls, out, on_exit)
      end
    end
    local function restore()
      executable.exists, vim.system, vim.uv.getaddrinfo = real_exists, real_system, real_getaddrinfo
      config.setup(nil)
    end

    --- Fetch `url` against the stubs and wait for the answer.
    ---@param url string
    ---@param opts table|nil display.remote overrides
    local function fetch(url, opts)
      config.setup({ display = { remote = vim.tbl_extend("force", { enabled = true }, opts or {}) } })
      local got, got_err, done
      remote.fetch(url, function(p, e)
        got, got_err, done = p, e, true
      end)
      vim.wait(5000, function()
        return done
      end, 10)
      return got, got_err, done
    end

    local function write(path, text)
      local f = assert(io.open(path, "wb"))
      f:write(text)
      f:close()
    end

    ---@param stdout string
    ---@param body string|nil
    ---@return fun(n: integer, out: string, on_exit: function): table
    local function respond(stdout, body)
      return function(_, out, on_exit)
        if body then write(out, body) end
        vim.schedule(function()
          on_exit({ code = 0, signal = 0, stdout = stdout, stderr = "" })
        end)
        return {}
      end
    end

    local ok, fail = pcall(function()
      -- A public name that redirects to the metadata endpoint: the second hop
      -- is refused, before any request is made to it.
      install()
      behave = respond("302\nhttp://169.254.169.254/latest/meta-data/", "x")
      local url = "https://img.example.com/images-nvim-redirect-private.png"
      local path, perr = fetch(url)
      H.falsy(path, "a redirect to a private address is not followed")
      H.contains(perr or "", "allow_private_hosts", "…and says why")
      H.eq(#calls, 1, "…the private target is never requested")
      H.ok(
        vim.tbl_contains(calls[1].cmd, "img.example.com:443:93.184.216.34"),
        "…and the first hop is pinned to the address that was checked (no second lookup)"
      )
      H.falsy(vim.uv.fs_stat(calls[1].out), "…and no partial file is left behind")

      -- A public-looking name that resolves to a private address.
      install()
      resolver = function()
        return { { addr = "10.0.0.5", family = "inet" } }
      end
      behave = respond("200\n", "x")
      path, err = fetch("https://rebind.example.com/images-nvim-dns-private.png")
      H.falsy(path, "a name that resolves to a private address is refused")
      H.contains(err or "", "allow_private_hosts", "…with the same message")
      H.eq(#calls, 0, "…before any download starts")

      -- ...unless the user opted in.
      install()
      resolver = function()
        return { { addr = "10.0.0.5", family = "inet" } }
      end
      behave = respond("200\n", "abc")
      url = "https://intranet.example.com/images-nvim-optin.png"
      path, err = fetch(url, { allow_private_hosts = true })
      H.ok(path, "allow_private_hosts lets it through: " .. tostring(err))
      if path then pcall(os.remove, path) end

      -- A relative redirect is followed (one hop more), the result is stored
      -- only at the end, and nothing named *.part stays behind.
      install()
      url = "https://img.example.com/dir/images-nvim-redirect-ok.png"
      behave = function(n, out, on_exit)
        local expected = vim.fn.sha256(url)
        H.falsy(
          vim.uv.fs_stat(vim.fn.stdpath("cache") .. "/images.nvim/remote/" .. expected .. ".png"),
          "the cache path is empty while downloading (hop " .. n .. ")"
        )
        if n == 1 then return respond("302\nhttps://img.example.com/other/final.png", "redirect body")(n, out, on_exit) end
        return respond("200\n", "final bytes")(n, out, on_exit)
      end
      path, err = fetch(url)
      H.ok(path, "a redirect to another public URL is followed: " .. tostring(err))
      H.eq(#calls, 2, "…in a second request")
      H.eq(calls[2] and calls[2].url, "https://img.example.com/other/final.png", "…to the target the server named")
      if path then
        local f = assert(io.open(path, "rb"))
        H.eq(f:read("*a"), "final bytes", "…and the cache holds the final body")
        f:close()
        pcall(os.remove, path)
      end
      H.eq(
        #vim.fn.glob(vim.fn.stdpath("cache") .. "/images.nvim/remote/*.part-*", false, true),
        0,
        "…and no .part file is left"
      )

      -- Redirect loops stop.
      install()
      behave = respond("302\nhttps://img.example.com/loop.png", "x")
      path, err = fetch("https://img.example.com/images-nvim-loop.png")
      H.falsy(path, "a redirect loop yields no file")
      H.contains(err or "", "too many redirects", "…and says so")
      H.eq(#calls, 6, "…after the first request plus five redirects")

      -- A redirect to another scheme is refused.
      install()
      behave = respond("302\nfile:///etc/passwd", "x")
      path, err = fetch("https://img.example.com/images-nvim-scheme.png")
      H.falsy(path, "a redirect to file:// yields no file")
      H.contains(err or "", "not an http", "…and says so")

      -- A body over the limit is discarded even if the tool did not stop it.
      install()
      behave = respond("200\n", string.rep("x", 50))
      url = "https://img.example.com/images-nvim-big.png"
      path, err = fetch(url, { max_bytes = 10 })
      H.falsy(path, "an oversized body yields no file")
      H.contains(err or "", "byte limit", "…and names the limit")
      H.falsy(vim.uv.fs_stat(calls[1].out), "…the partial file is removed")

      -- A body that grows past the limit while the tool is still running (wget
      -- ignores -Q, a chunked response has no announced size) is stopped.
      install()
      local killed
      behave = function(_, out, on_exit)
        write(out, string.rep("x", 50))
        return {
          kill = function(_, sig)
            killed = sig
            vim.schedule(function()
              on_exit({ code = -9, signal = 9, stdout = "", stderr = "" })
            end)
          end,
        }
      end
      path, err = fetch("https://img.example.com/images-nvim-grow.png", { max_bytes = 10 })
      H.eq(killed, 9, "a running download past the limit is killed")
      H.falsy(path, "…yielding no file")
      H.contains(err or "", "byte limit", "…and names the limit")
    end)
    restore()
    if not ok then error(fail, 0) end
  end
end
