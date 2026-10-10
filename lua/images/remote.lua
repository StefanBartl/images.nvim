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

-- ── Which hosts a document may make the editor talk to ──────────────────────
--
-- A markdown file decides the URL, so the URL is untrusted. Without a check it
-- can point the editor at localhost, the router or a cloud metadata endpoint.
-- Everything below works on spellings, because that is all there is before the
-- connection is made -- except `check_host`, which also asks the resolver.

local MAX_REDIRECTS = 5

local PRIVATE_ERR = "refusing to fetch a local/private address (`display.remote.allow_private_hosts = true` to allow)"

--- The host part of an http(s) URL, lower-cased, without userinfo and port;
--- IPv6 literals come back without their brackets. `nil` for anything a
--- parser could read differently from curl (backslashes, whitespace, control
--- characters in the authority) -- those are refused rather than guessed at.
---@param url string
---@return string|nil
local function url_host(url)
  local authority = url:match("^https?://([^/?#]*)")
  if not authority or authority:find("[%s%c\\]") then return nil end
  authority = authority:gsub("^.*@", "")
  local bracketed = authority:match("^%[([^%]]*)%]")
  local host = bracketed or authority:gsub(":%d*$", "")
  return host:lower()
end

---@param p string
---@return boolean
local function looks_numeric(p)
  return p:match("^%d+$") ~= nil or p:match("^0[xX]%x*$") ~= nil
end

--- One component of an `inet_aton`-style address: `0x1f` hex, `017` octal,
--- otherwise decimal. `nil` for an invalid one such as `08`.
---@param p string
---@return number|nil
local function numeric_part(p)
  if p:match("^0[xX]%x*$") then return tonumber(p:sub(3), 16) or 0 end
  if p:match("^0[0-7]*$") then return tonumber(p, 8) or 0 end
  if p:match("^[1-9]%d*$") then return tonumber(p) end
  return nil
end

--- An IPv4 address in any spelling curl and the system resolver accept:
--- `127.0.0.1`, `127.1`, `2130706433`, `0x7f.1`, `0177.0.0.1`.
---@param host string
---@return number|nil address 32-bit value
---@return boolean numeric the host is made of such components at all; with `address == nil` that means "numeric but invalid" and is refused
local function parse_v4(host)
  local parts = vim.split(host, ".", { plain = true })
  for _, p in ipairs(parts) do
    if not looks_numeric(p) then return nil, false end
  end
  if #parts > 4 then return nil, true end
  local value = 0
  for i, p in ipairs(parts) do
    local v = numeric_part(p)
    if not v then return nil, true end
    if i < #parts then
      if v > 255 then return nil, true end
      value = value + v * 256 ^ (4 - i)
    else
      if v >= 256 ^ (5 - #parts) then return nil, true end
      value = value + v
    end
  end
  return value, true
end

---@param n number 32-bit address
---@return boolean
local function v4_is_private(n)
  local a = math.floor(n / 16777216)
  local b = math.floor(n / 65536) % 256
  return a == 0 -- "this network"
    or a == 10
    or a == 127
    or (a == 100 and b >= 64 and b <= 127) -- CGNAT
    or (a == 169 and b == 254) -- link-local, cloud metadata
    or (a == 172 and b >= 16 and b <= 31)
    or (a == 192 and b == 168)
    or a >= 224 -- multicast, reserved, broadcast
end

--- An IPv6 literal as eight 16-bit groups, `nil` when malformed.
---@param s string
---@return integer[]|nil
local function parse_v6(s)
  local tail = s:match("(%d+%.%d+%.%d+%.%d+)$")
  if tail then
    local n = parse_v4(tail)
    if not n then return nil end
    s = s:sub(1, #s - #tail) .. ("%x:%x"):format(math.floor(n / 65536), n % 65536)
  end

  ---@param str string
  ---@return integer[]|nil
  local function groups(str)
    local list = {}
    if str == "" then return list end
    for g in (str .. ":"):gmatch("([^:]*):") do
      if not g:match("^%x%x?%x?%x?$") then return nil end
      list[#list + 1] = tonumber(g, 16)
    end
    return list
  end

  local gap = s:find("::", 1, true)
  if not gap then
    local all = groups(s)
    return all and #all == 8 and all or nil
  end
  if s:find("::", gap + 1, true) then return nil end
  local head, rest = groups(s:sub(1, gap - 1)), groups(s:sub(gap + 2))
  if not head or not rest or #head + #rest > 7 then return nil end
  local all = head
  for _ = 1, 8 - #head - #rest do
    all[#all + 1] = 0
  end
  for _, g in ipairs(rest) do
    all[#all + 1] = g
  end
  return all
end

---@param g integer[] eight groups
---@return boolean
local function v6_is_private(g)
  local function zeros(from, to)
    for i = from, to do
      if g[i] ~= 0 then return false end
    end
    return true
  end
  local function embedded(hi, lo)
    return v4_is_private(g[hi] * 65536 + g[lo])
  end
  if zeros(1, 6) then return embedded(7, 8) end -- ::, ::1, ::a.b.c.d
  if zeros(1, 5) and g[6] == 0xffff then return embedded(7, 8) end -- ::ffff:a.b.c.d
  if g[1] == 0x64 and g[2] == 0xff9b and zeros(3, 6) then return embedded(7, 8) end -- NAT64
  if g[1] == 0x2002 then return embedded(2, 3) end -- 6to4
  return g[1] >= 0xff00 -- multicast
    or (g[1] >= 0xfe80 and g[1] <= 0xfebf) -- link-local
    or (g[1] >= 0xfc00 and g[1] <= 0xfdff) -- unique local
    or (g[1] >= 0xfec0 and g[1] <= 0xfeff) -- site-local (deprecated)
end

--- Name suffixes that only exist on a private network.
local PRIVATE_SUFFIXES = { "localhost", "local", "localdomain", "internal", "lan", "home.arpa" }

---@param host string
---@return boolean
local function host_is_private(host)
  host = host:gsub("%.+$", "") -- "localhost." is localhost
  if host == "" or host:find("[%%%s%c\\]") then return true end -- percent-encoded or zoned hosts: refused, not decoded

  if host:find(":", 1, true) then
    local g = parse_v6(host)
    return g == nil or v6_is_private(g)
  end

  local n, numeric = parse_v4(host)
  if n then return v4_is_private(n) end
  if numeric then return true end

  if not host:find(".", 1, true) then return true end -- a single label ("intranet", "router") resolves via the search domain
  for _, suffix in ipairs(PRIVATE_SUFFIXES) do
    if host == suffix or host:sub(-#suffix - 1) == "." .. suffix then return true end
  end
  return false
end

--- Whether `url` points at this machine or a private network by its host's
--- spelling: `localhost`, loopback, RFC1918, link-local (cloud metadata lives
--- at 169.254.169.254), CGNAT, IPv6 loopback/unique-local/link-local (also
--- when embedded as IPv4-mapped, NAT64 or 6to4), numeric spellings of IPv4
--- (`2130706433`, `0x7f.1`, `0177.0.0.1`), single-label and `.local`-style
--- names. A DNS name is judged by `check_host`, which also resolves it.
---@param url string
---@return boolean
function M.is_private_host(url)
  local host = url_host(url)
  if not host then return true end
  return host_is_private(host)
end

---@param addr string an address as the resolver returns it
---@return boolean
local function addr_is_private(addr)
  if addr:find(":", 1, true) then
    local g = parse_v6(addr:lower())
    return g == nil or v6_is_private(g)
  end
  local n = parse_v4(addr)
  return n == nil or v4_is_private(n)
end

--- Judge `url`'s host, hop by hop: by its spelling, and for a DNS name also by
--- what it resolves to (a public-looking name such as `127.0.0.1.nip.io` or an
--- attacker's own record pointing at 169.254.169.254).
---
--- For a DNS name the checked address is handed back as `pin` (curl's
--- `--resolve host:port:addr`), so the download connects to exactly what was
--- judged here and a server answering differently the second time (DNS
--- rebinding) gains nothing. wget has no such option and asks the resolver
--- again; neither tool is pinned when a proxy from the environment decides
--- where the connection goes.
---@param url string
---@param allow boolean `display.remote.allow_private_hosts`
---@param cb fun(err: string|nil, pin: string|nil)
---@return nil
local function check_host(url, allow, cb)
  if allow then return cb(nil) end
  local host = url_host(url)
  if not host or host_is_private(host) then return cb(PRIVATE_ERR) end
  if host:find(":", 1, true) or parse_v4(host) then return cb(nil) end -- a public literal: nothing to resolve

  local started = vim.uv.getaddrinfo(host, nil, { socktype = "stream" }, function(err, res)
    vim.schedule(function()
      -- A failed lookup is the download tool's to report.
      if err or not res then return cb(nil) end
      local chosen
      for _, r in ipairs(res) do
        if r.addr then
          if addr_is_private(r.addr) then return cb(PRIVATE_ERR) end
          chosen = chosen or r.addr
        end
      end
      if not chosen then return cb(nil) end
      local port = url:match("^https?://[^/?#]*:(%d+)[/?#]") or url:match("^https?://[^/?#]*:(%d+)$")
      port = port or (url:match("^https:") and "443" or "80")
      cb(nil, ("%s:%s:%s"):format(host, port, chosen:find(":", 1, true) and ("[" .. chosen .. "]") or chosen))
    end)
  end)
  if not started then cb(nil) end
end

--- An absolute URL for the `Location` of a redirect from `base`.
---@param base string
---@param location string
---@return string|nil
local function resolve_location(base, location)
  if location:match("^%a[%w+.-]*:") then return location end
  local scheme, authority = base:match("^(https?)://([^/?#]*)")
  if not scheme then return nil end
  if location:sub(1, 2) == "//" then return scheme .. ":" .. location end
  if location:sub(1, 1) == "/" then return scheme .. "://" .. authority .. location end
  local without_query = base:gsub("[?#].*$", "")
  local dir = without_query:match("^(https?://[^/]+.*)/[^/]*$") or (scheme .. "://" .. authority)
  return dir .. "/" .. location
end

--- The download command for `tool`, fetching ONE hop.
---
--- **Redirects are not followed by the tool.** `curl -L` would follow a
--- redirect from a public server to `http://169.254.169.254/` before anything
--- here could look at it, so neither tool is allowed to: `M.fetch` reads the
--- redirect target, checks the new host like the first one and starts the next
--- hop itself (at most `MAX_REDIRECTS`).
---
--- curl reports the status and redirect target on stdout (`-w`). wget, which
--- cannot, prints the response headers to stderr (`-S`). `--globoff` keeps
--- curl from expanding `[1-3]` or `{a,b}` in a URL into several requests.
---
--- Size: curl stops at `--max-filesize`; wget's `-Q` never limits a single
--- file fetched with `-O` (measured: a 4 MB chunked response arrived whole
--- under `-Q100000`), so `run` watches the file instead.
---@param tool "curl"|"wget"
---@param url string
---@param out string
---@param timeout_s integer
---@param max_bytes integer
---@param pin string|nil curl `--resolve` value from `check_host`
---@return string[]
function M.build_cmd(tool, url, out, timeout_s, max_bytes, pin)
  if tool == "curl" then
    local cmd = {
      "curl",
      "-fsS",
      "--globoff",
      "--proto",
      "=http,https",
      "--max-time",
      tostring(timeout_s),
      "--max-filesize",
      tostring(max_bytes),
      "-o",
      out,
      "-w",
      "%{http_code}\n%{redirect_url}",
    }
    if pin then
      table.insert(cmd, "--resolve")
      table.insert(cmd, pin)
    end
    table.insert(cmd, url)
    return cmd
  end
  return { "wget", "-q", "-S", "--tries=1", "--timeout=" .. tostring(timeout_s), "--max-redirect=0", "-O", out, url }
end

--- Run `cmd` and kill it as soon as `out` grows past `max_bytes`.
---@param cmd string[]
---@param out string file the tool writes
---@param max_bytes integer
---@param timeout_s integer wall-clock bound for the whole process (wget has none of its own)
---@param on_exit fun(result: vim.SystemCompleted, over_limit: boolean)
---@return nil
local function run(cmd, out, max_bytes, timeout_s, on_exit)
  local over_limit, finished = false, false
  local timer ---@type uv.uv_timer_t|nil
  local function stop_timer()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  local ok, proc = pcall(vim.system, cmd, { text = true, timeout = (timeout_s + 2) * 1000 }, function(result)
    finished = true
    stop_timer()
    on_exit(result, over_limit)
  end)
  if not ok then return on_exit({ code = -1, signal = 0, stdout = "", stderr = tostring(proc) }, false) end

  if finished then return end
  timer = assert(vim.uv.new_timer())
  timer:start(250, 250, function()
    local stat = vim.uv.fs_stat(out)
    if stat and stat.size > max_bytes then
      over_limit = true
      stop_timer()
      pcall(proc.kill, proc, 9)
    end
  end)
end

---@param status integer|nil
---@return boolean
local function is_redirect(status)
  return status == 301 or status == 302 or status == 303 or status == 307 or status == 308
end

--- Download the image at `url`, cached — a second call with the same URL does
--- not download again but hits the cache.
---
--- Asynchronous: the result arrives exclusively via `on_done`. The download
--- used to run through `vim.system(...):wait()` and held the UI thread for the
--- entire transfer — on a slow line, up to the configured timeout (default
--- 10s). A cache hit calls `on_done` within the same tick, with no process at
--- all.
---
--- The bytes go to a `.part` file next to the cache entry and are moved into
--- place only after the size has been checked: the cache path never holds a
--- half-written file that the TTL check above would serve as fresh.
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
  local max_bytes = math.floor(valid_positive(c.max_bytes, 20 * 1024 * 1024))
  local allow_private = c.allow_private_hosts == true

  if not allow_private and M.is_private_host(url) then return on_done(nil, PRIVATE_ERR) end

  local executable = require("lib.nvim.cross.executable")
  local tool ---@type "curl"|"wget"
  if executable.exists("curl") then
    tool = "curl"
  elseif executable.exists("wget") then
    tool = "wget"
  else
    return on_done(nil, "neither `curl` nor `wget` found")
  end

  local part = ("%s.part-%d-%d"):format(out, vim.uv.os_getpid(), vim.uv.hrtime() % 1e9)
  local limit_err = ("download exceeds the %d byte limit (`display.remote.max_bytes`)"):format(max_bytes)

  ---@param msg string
  local function fail(msg)
    pcall(vim.uv.fs_unlink, part)
    on_done(nil, msg)
  end

  ---@param current string
  ---@param hops integer redirects followed so far
  local function hop(current, hops)
    check_host(current, allow_private, function(host_err, pin)
      if host_err then return fail(host_err) end

      local cmd = M.build_cmd(tool, current, part, timeout_s, max_bytes, pin)
      run(cmd, part, max_bytes, timeout_s, function(result, over_limit)
        -- vim.system callbacks run outside the main loop; the caller draws to
        -- the terminal and notifies afterwards.
        vim.schedule(function()
          if over_limit then return fail(limit_err) end

          local status, location
          if tool == "curl" then
            if result.code ~= 0 then
              return fail(("download failed (exit %d): %s"):format(result.code, vim.trim(result.stderr or "")))
            end
            local code, target = (result.stdout or ""):match("^(%d+)\n?([^\r\n]*)")
            status, location = tonumber(code), target
          else
            local err = result.stderr or ""
            for s in err:gmatch("HTTP/%d%.?%d?%s+(%d%d%d)") do
              status = tonumber(s)
            end
            for l in err:gmatch("[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:%s*([^\r\n]+)") do
              location = l
            end
            if result.code == 0 then
              status = 200
            elseif not (is_redirect(status) and location) then
              local why = status and ("HTTP " .. status) or vim.trim(err:match("([^\r\n]*)%s*$") or "")
              return fail(("download failed (exit %d): %s"):format(result.code, why))
            end
          end

          if is_redirect(status) then
            if not location or location == "" then return fail("redirect without a target") end
            if hops >= MAX_REDIRECTS then return fail("too many redirects") end
            local nxt = resolve_location(current, location)
            if not nxt or not M.is_remote(nxt) then return fail("redirect to something that is not an http(s) URL") end
            return hop(nxt, hops + 1)
          end

          local stat = vim.uv.fs_stat(part)
          if not stat or stat.size == 0 then return fail("download produced no file") end
          if stat.size > max_bytes then return fail(limit_err) end

          local renamed, rename_err = vim.uv.fs_rename(part, out)
          if not renamed then return fail("could not store the download: " .. tostring(rename_err)) end
          on_done(out, nil)
        end)
      end)
    end)
  end

  hop(url, 0)
end

return M
