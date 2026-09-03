-- TESTS/testcard_spec.lua — the hand-rolled PNG writer.
--
-- Building a valid PNG without external tools is exactly the kind of code that
-- can be quietly wrong: a header every parser accepts, carrying a checksum
-- every decoder chokes on. That is precisely how the first version failed
-- (LuaJIT evaluates bit operations as signed, so the division-as-shift variant
-- produced wrong CRCs). Hence the structure is recomputed here rather than
-- merely checked for "looks like a PNG".

---@param H table harness from TESTS/run.lua
return function(H)
  local testcard = require("images.testcard")

  ---@param s string
  ---@param off integer 1-based
  ---@return integer
  local function be32_at(s, off)
    return s:byte(off) * 0x1000000 + s:byte(off + 1) * 0x10000 + s:byte(off + 2) * 0x100 + s:byte(off + 3)
  end

  -- ── size_for: the card adopts the cell box's aspect ratio ────────────────
  -- The module's entire purpose. Get this wrong and the terminal letterboxes,
  -- so calibration measures the letterbox border instead of the placement.
  local size = testcard.size_for(60, 20, 0.46)
  local want = (60 * 0.46) / 20
  local got = size.width / size.height
  H.ok(math.abs(got - want) < 0.01, ("size_for matches the box aspect ratio (%.4f ~ %.4f)"):format(got, want))
  H.ok(math.max(size.width, size.height) <= testcard.LONG_EDGE, "…and stays within LONG_EDGE")

  -- A very tall box: the long edge is then the height, not the width.
  local tall = testcard.size_for(10, 40, 0.5)
  H.ok(tall.height >= tall.width, "a tall box yields a tall card")
  H.ok(math.max(tall.width, tall.height) <= testcard.LONG_EDGE, "…also within LONG_EDGE")

  -- Degenerate input must not produce a zero-pixel edge: OSC 1337 would send
  -- an empty file and the terminal would draw nothing.
  local tiny = testcard.size_for(1, 1, 0.5)
  H.ok(tiny.width >= 8 and tiny.height >= 8, "a tiny box still yields a drawable card")

  -- ── build: PNG structure ──────────────────────────────────────────────────
  local png = testcard.build(64, 32)
  H.eq(png:sub(1, 8), "\137PNG\r\n\26\n", "PNG signature is correct")

  -- Walk the chunk chain, checking that the length fields are consistent — a
  -- field that is too short or too long fails here rather than later in the
  -- terminal's decoder.
  local seen, off = {}, 9
  while off < #png do
    local len = be32_at(png, off)
    local kind = png:sub(off + 4, off + 7)
    seen[#seen + 1] = kind
    off = off + 12 + len
  end
  H.eq(off, #png + 1, "chunk lengths add up to exactly the file size")
  H.eq(seen[1], "IHDR", "first chunk is IHDR")
  H.eq(seen[#seen], "IEND", "last chunk is IEND")
  H.ok(vim.tbl_contains(seen, "IDAT"), "there is an IDAT chunk")

  -- IHDR contents: dimensions and colour type exactly as the caller ordered.
  H.eq(be32_at(png, 17), 64, "IHDR reports the requested width")
  H.eq(be32_at(png, 21), 32, "IHDR reports the requested height")
  H.eq(png:byte(25), 8, "bit depth 8")
  H.eq(png:byte(26), 2, "colour type 2 (RGB without alpha)")

  -- ── CRC: the bug the first version died on ───────────────────────────────
  -- Neovim exposes no CRC-32 function, so an independent reference
  -- implementation is computed here — deliberately written differently from
  -- the one in the module (table per call, no memoization), so that a shared
  -- thinking error cannot make both wrong at once.
  ---@param s string
  ---@return integer
  local function reference_crc32(s)
    local tbl = {}
    for i = 0, 255 do
      local c = i
      for _ = 1, 8 do
        c = (c % 2 == 1) and bit.bxor(0xEDB88320, bit.rshift(c, 1)) or bit.rshift(c, 1)
      end
      tbl[i] = c
    end
    local crc = bit.bnot(0)
    for i = 1, #s do
      crc = bit.bxor(tbl[bit.band(bit.bxor(crc, s:byte(i)), 0xFF)], bit.rshift(crc, 8))
    end
    return bit.bxor(crc, bit.bnot(0)) % 0x100000000
  end

  local checked, pos = 0, 9
  while pos < #png do
    local len = be32_at(png, pos)
    local body = png:sub(pos + 4, pos + 7 + len) -- type + payload
    local stored = be32_at(png, pos + 8 + len)
    H.eq(stored, reference_crc32(body), ("CRC of %s is correct"):format(png:sub(pos + 4, pos + 7)))
    checked = checked + 1
    pos = pos + 12 + len
  end
  H.ok(checked >= 3, "all chunks were checked (IHDR/IDAT/IEND)")

  -- ── IDAT: zlib framing and raw data length ───────────────────────────────
  -- The stream consists of *stored* blocks; the decompressed size must be
  -- exactly `height * (1 + width * 3)` (one filter byte per row plus RGB).
  local idat_pos, idat_len = nil, nil
  pos = 9
  while pos < #png do
    local len = be32_at(png, pos)
    if png:sub(pos + 4, pos + 7) == "IDAT" then
      idat_pos, idat_len = pos + 8, len
      break
    end
    pos = pos + 12 + len
  end
  H.ok(idat_pos ~= nil, "IDAT found")
  -- ...and stop here if it was not. Everything below indexes into the chunk,
  -- where a missing IDAT would surface five lines on as arithmetic on a nil
  -- value rather than as the check that failed.
  -- Under new names rather than shadowing: the point of the line is to narrow
  -- `integer|nil` to `integer` for what follows, and a second local of the same
  -- name says that to LuaLS while reading to luacheck as an accident.
  local idat_at, idat_size = assert(idat_pos), assert(idat_len)

  local idat = png:sub(idat_at, idat_at + idat_size - 1)
  H.eq(idat:byte(1), 0x78, "zlib header CMF = 0x78")

  -- Walk the stored blocks: header (1 byte), LEN, NLEN, data. LEN and NLEN
  -- must complement each other to 0xFFFF, or every decoder rejects the stream.
  -- Start at 3: the two zlib header bytes (CMF/FLG) come before that.
  local p, payload, final = 3, 0, 0
  while p < idat_size do
    final = idat:byte(p)
    local blen = idat:byte(p + 1) + idat:byte(p + 2) * 256
    local nlen = idat:byte(p + 3) + idat:byte(p + 4) * 256
    H.eq(blen + nlen, 0xFFFF, "LEN and NLEN complement to 0xFFFF")
    payload = payload + blen
    p = p + 5 + blen
    if final == 1 then break end
  end
  H.eq(final, 1, "the last block is marked final")
  H.eq(payload, 32 * (1 + 64 * 3), "decompressed size = height * (1 + width * 3)")
  H.eq(p + 4, idat_size + 1, "exactly 4 bytes of Adler-32 follow the last block")
end
