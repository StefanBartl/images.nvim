-- TESTS/pixels_spec.lua — how large a picture is, from its own header.
--
-- Unlike most of this suite there is nothing here that needs a terminal or an
-- external tool, and that is the point of the module: the draw path's layout
-- arithmetic must not depend on ImageMagick being installed. So the headers
-- are built byte by byte, with dimensions chosen to be asymmetric (a reader
-- that swaps width and height, or reads the wrong endianness, has to fail) and
-- larger than 255 (one that reads a single byte has to fail too).

---@param H table harness from TESTS/run.lua
return function(H)
  local pixels = require("images.pixels")

  ---@param n integer
  ---@return string
  local function be32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end

  ---@param n integer
  ---@return string
  local function le32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
  end

  ---@param n integer
  ---@return string
  local function le16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
  end

  ---@param n integer
  ---@return string
  local function be16(n)
    return string.char(math.floor(n / 256) % 256, n % 256)
  end

  ---@param n integer
  ---@return string
  local function le24(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256)
  end

  H.tmpdir(function(dir)
    ---@param name string
    ---@param bytes string
    ---@return Images.Scale.Dims|nil
    local function dims_of(name, bytes)
      local path = dir .. "/" .. name
      H.write(path, bytes)
      return pixels.read(path)
    end

    -- ── PNG ─────────────────────────────────────────────────────────────────
    local png = dims_of("a.png", "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(993) .. be32(1404) .. "\8\6\0\0\0")
    H.ok(png ~= nil, "a PNG header is read")
    H.eq(png and png.width, 993, "…its width")
    H.eq(png and png.height, 1404, "…and its height, not the other way round")

    -- ── GIF ─────────────────────────────────────────────────────────────────
    local gif = dims_of("a.gif", "GIF89a" .. le16(640) .. le16(480) .. "\0\0\0")
    H.ok(gif ~= nil, "a GIF header is read")
    H.eq(gif and gif.width, 640, "…its width")
    H.eq(gif and gif.height, 480, "…and its height")

    -- ── BMP, including the top-down variant with a negative height ──────────
    local bmp = dims_of("a.bmp", "BM" .. ("\0"):rep(16) .. le32(300) .. le32(200) .. ("\0"):rep(8))
    H.ok(bmp ~= nil, "a BMP header is read")
    H.eq(bmp and bmp.width, 300, "…its width")
    H.eq(bmp and bmp.height, 200, "…and its height")

    local flipped = dims_of("flip.bmp", "BM" .. ("\0"):rep(16) .. le32(300) .. le32(4294967096) .. ("\0"):rep(8))
    H.eq(flipped and flipped.height, 200, "a top-down BMP is 200 rows tall, not minus 200")

    -- ── WebP, all three containers ──────────────────────────────────────────
    local vp8x = dims_of("x.webp", "RIFF" .. le32(0) .. "WEBP" .. "VP8X" .. le32(10) .. "\0\0\0\0" .. le24(992) .. le24(1403))
    H.ok(vp8x ~= nil, "an extended WebP header is read")
    H.eq(vp8x and vp8x.width, 993, "…its width is the stored value plus one")
    H.eq(vp8x and vp8x.height, 1404, "…and so is its height")

    local vp8 =
      dims_of("l.webp", "RIFF" .. le32(0) .. "WEBP" .. "VP8 " .. le32(10) .. "\0\0\0" .. "\157\1\42" .. le16(640) .. le16(480))
    H.eq(vp8 and vp8.width, 640, "a lossy WebP's width")
    H.eq(vp8 and vp8.height, 480, "…and height")

    -- 14 bits of (width-1), then 14 bits of (height-1): 639 | 479 << 14.
    local packed = 639 + 479 * 16384
    local vp8l = dims_of("ll.webp", "RIFF" .. le32(0) .. "WEBP" .. "VP8L" .. le32(10) .. "\47" .. le32(packed) .. "\0\0\0\0")
    H.eq(vp8l and vp8l.width, 640, "a lossless WebP's width")
    H.eq(vp8l and vp8l.height, 480, "…and height")

    -- ── JPEG: the frame header has to be WALKED to, past whatever precedes it ─
    local app0 = "\255\224" .. be16(16) .. ("\0"):rep(14)
    local sof0 = "\255\192" .. be16(17) .. "\8" .. be16(1404) .. be16(993) .. ("\0"):rep(10)
    local jpg = dims_of("a.jpg", "\255\216" .. app0 .. sof0 .. "\255\218")
    H.ok(jpg ~= nil, "a JPEG frame header is found behind an APP0 segment")
    H.eq(jpg and jpg.width, 993, "…its width, which is stored second")
    H.eq(jpg and jpg.height, 1404, "…and its height, which is stored first")

    -- A JPEG whose scan starts before any frame header: nothing to find, and
    -- the walk has to stop rather than read the entropy-coded data as markers.
    local truncated = dims_of("cut.jpg", "\255\216" .. app0 .. "\255\218" .. ("\170"):rep(200))
    H.eq(truncated, nil, "a JPEG with no frame header before the scan yields nothing")

    -- ── The honest nils ─────────────────────────────────────────────────────
    H.eq(dims_of("a.svg", '<svg width="10" height="10"></svg>'), nil, "an SVG states no pixels")
    H.eq(dims_of("a.txt", "just text"), nil, "an unknown container yields nothing")
    H.eq(dims_of("empty.png", ""), nil, "an empty file yields nothing")
    H.eq(dims_of("short.png", "\137PNG\r\n\26\n"), nil, "a PNG signature with no IHDR behind it yields nothing")
    H.eq(pixels.read(dir .. "/nope.png"), nil, "a file that is not there yields nothing")
    H.eq(pixels.read(nil), nil, "nil yields nothing")
    H.eq(pixels.read(""), nil, "the empty string yields nothing")

    -- ── The cache answers the same thing twice ──────────────────────────────
    local again = pixels.read(dir .. "/a.png")
    H.eq(again and again.width, 993, "a second read agrees with the first")
  end)
end
