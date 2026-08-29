---@module 'images.testcard'
---@brief Build a test card as a PNG, without external tools.
---@description
--- `images.calibrate` needs an image whose edges coincide with the draw box —
--- only then does "the card sticks out at the top" actually mean "placement
--- sits too low" rather than "the aspect ratio is off". A shipped PNG cannot
--- do that: the box depends on `display.cell_aspect` and the window size, so
--- it is only known at runtime. Hence the card is built here, with exactly the
--- pixel aspect ratio the current box has in pixels — leaving the terminal
--- nothing to letterbox under `preserveAspectRatio=1`.
---
--- **Why a hand-rolled PNG writer instead of ImageMagick.** Calibration has to
--- work precisely where nothing is set up yet; a dependency you must install
--- first would be the wrong hurdle at this point (see the "ImageMagick
--- improves, but never enables" guardrail). PNG can
--- be written without compression: the zlib stream may consist of *stored*
--- blocks, which needs only CRC-32 and Adler-32, both a few lines. That makes
--- the file large, but it lives only for the duration of one calibration.

local M = {}

--- Edge length of the generated card in pixels (the longer axis). Small
--- enough to keep the uncompressed stream manageable, large enough for crisp
--- edges once the terminal has scaled it.
M.LONG_EDGE = 480

---@type integer[]|nil
local crc_table = nil

---@internal
--- `bit.*` throughout rather than division: LuaJIT evaluates bit operations
--- on *signed* 32-bit values, so anything from 0x80000000 up comes back
--- negative. A `math.floor(c / 2)` on such a value then shifts the wrong way
--- and the checksum is quietly wrong — a PNG every header parser accepts and
--- no decoder reads. `bit.rshift` shifts logically and avoids that.
---@return integer[]
local function crc32_table()
  if crc_table then return crc_table end
  crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if bit.band(c, 1) == 1 then
        c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
      else
        c = bit.rshift(c, 1)
      end
    end
    crc_table[i] = c
  end
  return crc_table
end

---@internal
---@param s string
---@return integer
local function crc32(s)
  local tbl = crc32_table()
  local c = bit.bnot(0) -- 0xFFFFFFFF
  for i = 1, #s do
    c = bit.bxor(tbl[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
  end
  return bit.bxor(c, bit.bnot(0)) % 0x100000000
end

---@internal
---@param n integer
---@return string
local function be32(n)
  n = n % 0x100000000
  return string.char(math.floor(n / 0x1000000) % 256, math.floor(n / 0x10000) % 256, math.floor(n / 0x100) % 256, n % 256)
end

---@internal
---@param kind string
---@param payload string
---@return string
local function chunk(kind, payload)
  return be32(#payload) .. kind .. payload .. be32(crc32(kind .. payload))
end

---@internal
--- A zlib stream without compression: header, *stored* blocks, Adler-32.
---@param raw string
---@return string
local function zlib_stored(raw)
  local parts = { "\120\001" } -- CMF/FLG for "deflate, no preset"

  local pos, n = 1, #raw
  repeat
    local len = math.min(65535, n - pos + 1)
    local final = (pos + len - 1 >= n) and 1 or 0
    parts[#parts + 1] = string.char(final)
    parts[#parts + 1] = string.char(len % 256, math.floor(len / 256) % 256)
    local nlen = 0xFFFF - len
    parts[#parts + 1] = string.char(nlen % 256, math.floor(nlen / 256) % 256)
    parts[#parts + 1] = raw:sub(pos, pos + len - 1)
    pos = pos + len
  until pos > n

  local a, b = 1, 0
  for i = 1, n do
    a = (a + raw:byte(i)) % 65521
    b = (b + a) % 65521
  end
  parts[#parts + 1] = be32(b * 65536 + a)

  return table.concat(parts)
end

---@class Images.Testcard.Size
---@field width integer pixels
---@field height integer pixels

--- Pixel dimensions for a cell box, such that the image fills it exactly.
--- This is the whole point of the module: the card adopts the box's aspect
--- ratio, rather than the box having to accommodate the card.
---@param cols integer draw box width in cells
---@param rows integer draw box height in cells
---@param cell_aspect number width/height of one cell
---@return Images.Testcard.Size
function M.size_for(cols, rows, cell_aspect)
  local w = cols * cell_aspect
  local h = rows
  local scale = M.LONG_EDGE / math.max(w, h)
  return {
    width = math.max(8, math.floor(w * scale + 0.5)),
    height = math.max(8, math.floor(h * scale + 0.5)),
  }
end

--- Build a test card as PNG bytes.
---
--- The pattern is designed around exactly one question: "does the image's edge
--- touch the window's edge?". Hence a solid, closed frame right at the border
--- plus a corner block in a second colour — if a stretch of frame is missing
--- on one side, the image is cut off there; if there is a gap between frame
--- and window border, the image sits too far in. The centre cross adds a sense
--- of "by how much" by splitting the area into visible quarters.
---@param width integer pixels
---@param height integer pixels
---@return string png raw file bytes
function M.build(width, height)
  width, height = math.max(8, width), math.max(8, height)

  -- Frame thickness: visible, but never more than an eighth of the short
  -- edge, so the pattern stays readable even in a very narrow box.
  local border = math.max(2, math.floor(math.min(width, height) / 24))
  local corner = math.max(border * 3, math.floor(math.min(width, height) / 6))

  local BG = { 0x12, 0x14, 0x1A }
  local FRAME = { 0xE6, 0xB4, 0x50 } -- warm, stands out against any theme
  local CORNER = { 0x4F, 0xC3, 0xF7 }
  local CROSS = { 0x55, 0x5A, 0x66 }

  local rows_out = {}
  for y = 0, height - 1 do
    local line = { "\0" } -- filter "None"
    for x = 0, width - 1 do
      local c = BG

      local near_v = x < border or x >= width - border
      local near_h = y < border or y >= height - border
      if near_v or near_h then
        c = FRAME
        -- Corners in a different colour: they reveal WHICH edge is missing
        -- when only part of the image is cut off.
        local in_corner = (x < corner or x >= width - corner) and (y < corner or y >= height - corner)
        if in_corner then c = CORNER end
      elseif x == math.floor(width / 2) or y == math.floor(height / 2) then
        c = CROSS
      end

      line[#line + 1] = string.char(c[1], c[2], c[3])
    end
    rows_out[#rows_out + 1] = table.concat(line)
  end

  local ihdr = be32(width) .. be32(height) .. string.char(8, 2, 0, 0, 0)
  return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr) .. chunk("IDAT", zlib_stored(table.concat(rows_out))) .. chunk("IEND", "")
end

--- Write a test card for `cols`x`rows` to a temporary file.
---@param cols integer
---@param rows integer
---@param cell_aspect number
---@return string|nil path
---@return string|nil err
function M.write(cols, rows, cell_aspect)
  local size = M.size_for(cols, rows, cell_aspect)
  local ok, png = pcall(M.build, size.width, size.height)
  if not ok then return nil, "could not build the test card: " .. tostring(png) end

  local path = vim.fn.tempname() .. "-images-testcard.png"
  local f, ferr = io.open(path, "wb")
  if not f then return nil, "test card not writable: " .. tostring(ferr) end
  f:write(png)
  f:close()
  return path
end

return M
