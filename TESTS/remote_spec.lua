-- TESTS/remote_spec.lua — remote image detection and the off-by-default state.
--
-- No real download in this test: `fetch` with the default
-- (`display.remote.enabled = false`) returns its error synchronously without
-- ever touching the network — precisely the case that must never fire a request
-- without consent.

---@param H table harness from TESTS/run.lua
return function(H)
  local remote = require("images.remote")

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
end
