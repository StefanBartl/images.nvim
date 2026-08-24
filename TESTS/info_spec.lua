-- TESTS/info_spec.lua — metadata formatting.
--
-- `collect` reads the filesystem and optionally shells out to ImageMagick;
-- what is checked here is the pure formatting, plus the behaviour for a
-- missing file.

---@param H table harness from TESTS/run.lua
return function(H)
  local info = require("images.info")

  -- ── human_size ─────────────────────────────────────────────────────────────
  H.eq(info.human_size(0), "0 B", "zero bytes")
  H.eq(info.human_size(512), "512 B", "below 1 KB stays in bytes, without a decimal")
  H.eq(info.human_size(1024), "1.0 KB", "exactly 1 KB tips into the next unit")
  H.eq(info.human_size(1536), "1.5 KB", "a decimal for fractional values")
  H.eq(info.human_size(1024 * 1024), "1.0 MB", "megabytes")
  H.eq(info.human_size(1024 * 1024 * 1024), "1.0 GB", "gigabytes")
  -- Nothing scales past GB: the unit list ends there, and an image beyond that
  -- is a special case anyway.
  H.contains(info.human_size(5 * 1024 * 1024 * 1024), "GB", "above GB it stays in GB")

  -- ── collect reports a missing file instead of throwing ─────────────────────
  local data, err = info.collect("/definitely/does/not/exist.png")
  H.falsy(data, "a missing file returns no data")
  H.contains(err or "", "not found", "…but a reason")

  -- ── lines() on a record without dimensions ─────────────────────────────────
  -- The no-ImageMagick case: size and date must still come out, or the feature
  -- would be worthless without the optional dependency.
  local lines = info.lines({
    path = "/tmp/x.png",
    bytes = 2048,
    mtime = 0,
    format = nil,
    width = nil,
    height = nil,
  })
  H.ok(#lines >= 2, "at least path and size")
  H.contains(table.concat(lines, "\n"), "2.0 KB", "size appears formatted")

  -- ── lines() with dimensions ────────────────────────────────────────────────
  lines = info.lines({
    path = "/tmp/x.png",
    bytes = 100,
    mtime = 0,
    format = "PNG",
    width = 200,
    height = 100,
  })
  local joined = table.concat(lines, "\n")
  H.contains(joined, "PNG 200x100", "format and dimensions on one line")
end
