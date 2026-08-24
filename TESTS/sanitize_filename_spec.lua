-- TESTS/sanitize_filename_spec.lua — file name cleaning for `:Image paste`.
--
-- A pure function, no terminal or filesystem needed — the same separation as
-- `images.gallery`/`images.scale`.

---@param H table harness from TESTS/run.lua
return function(H)
  local sanitize = require("images.paste").sanitize_filename

  -- ── The extension is always forced to .png ───────────────────────────────
  H.eq(sanitize("screenshot"), "screenshot.png", "without an extension, .png is appended")
  H.eq(sanitize("screenshot.jpg"), "screenshot.png", "a different extension is replaced")
  H.eq(sanitize("screenshot.png"), "screenshot.png", "an already matching extension stays")
  H.eq(sanitize("archive.tar.gz"), "archive.tar.png", "only the last extension is replaced")

  -- ── Path components are discarded, not honoured ──────────────────────────
  H.eq(sanitize("../../etc/passwd"), "passwd.png", "directory components are dropped, no escape from paste.dir")
  H.eq(sanitize("sub/dir/name"), "name.png", "an ordinary subpath is reduced to the name too")
  H.eq(sanitize("C:\\Windows\\name"), "name.png", "Windows backslashes are treated the same way")

  -- ── Nothing usable left -> nil, not empty ────────────────────────────────
  H.eq(sanitize(""), nil, "empty input yields nil")
  H.eq(sanitize("   "), nil, "whitespace only yields nil")
  H.eq(sanitize(".."), nil, "'..' alone yields nil, not '...png'")
  H.eq(sanitize("."), nil, "'.' alone yields nil")
  H.eq(sanitize("../.."), nil, "pure traversal input yields nil")

  -- ── Whitespace around the name itself is stripped ────────────────────────
  H.eq(sanitize("  name  "), "name.png", "leading/trailing whitespace is trimmed")
end
