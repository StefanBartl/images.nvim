---@module 'images.pixels'
---@brief How large a picture is, read from its own header — no ImageMagick,
---no subprocess.
---@description
--- `images.info` answers the same question through `magick identify`, which is
--- correct, blocking, and only available when ImageMagick is. That is fine for
--- `:Image info`, where the dimensions are the *content*. It is not fine for
--- the draw path, where they are the *layout*: `images.anchor` needs an
--- image's aspect ratio to shape the box it hands the terminal, on every
--- draw, including a picker preview that redraws as the selection moves — and
--- including on a machine without ImageMagick, where a wrong box is a visibly
--- broken screen rather than a missing line of metadata. Per the plugin's own
--- guardrail, ImageMagick improves features and never enables them; a draw
--- that only lands correctly with ImageMagick installed would break it.
---
--- So: the first few dozen bytes of the file, which is where every raster
--- container states its size. PNG, JPEG, GIF, BMP and WebP — the whole of the
--- default `extensions` list except SVG, which states no pixel size because it
--- has none (it is converted to PNG before drawing, see `images.convert`; the
--- honest answer here is nil and callers fall back to their previous
--- behaviour).
---
--- **This is not a second opinion on `images.info`.** `info.collect` uses this
--- module when ImageMagick could not answer, so there is one number and two
--- routes to it rather than two numbers. Where both can answer they agree;
--- where they disagree the file is malformed and ImageMagick is the better
--- judge, which is why it goes first there.
---
--- hover.nvim carries an equivalent reader of its own (`hover.preview.media`'s
--- `pixel_size`) for the same reason and against the same formats. That
--- duplication is worth naming: this plugin is the one that ought to own it,
--- and a future hover.nvim can call this instead.

local M = {}

---@internal
--- Keyed by path plus mtime plus size, exactly like `images.info`'s cache: the
--- header only changes when the file does. `false` is cached too — an
--- unreadable or unsupported container must not be re-opened on every redraw.
---@type table<string, Images.Scale.Dims|false>
local cache = {}

-- ── Byte readers. 1-based offsets, the way Lua indexes strings. ─────────────

---@param s string
---@param i integer
---@return integer
local function u16be(s, i)
  return s:byte(i) * 256 + s:byte(i + 1)
end

---@param s string
---@param i integer
---@return integer
local function u16le(s, i)
  return s:byte(i) + s:byte(i + 1) * 256
end

---@param s string
---@param i integer
---@return integer
local function u32be(s, i)
  return ((s:byte(i) * 256 + s:byte(i + 1)) * 256 + s:byte(i + 2)) * 256 + s:byte(i + 3)
end

---@param s string
---@param i integer
---@return integer
local function u32le(s, i)
  return s:byte(i) + s:byte(i + 1) * 256 + s:byte(i + 2) * 65536 + s:byte(i + 3) * 16777216
end

-- ── Per-container readers. Each takes the first bytes already read, and the
--    open handle for the one format that cannot answer from a fixed offset. ──

--- PNG: an 8-byte signature, then the IHDR chunk, whose first two fields are
--- the dimensions. Fixed offsets, always.
---@param head string at least 24 bytes
---@return integer|nil width, integer|nil height
local function png(head)
  if #head < 24 or head:sub(1, 8) ~= "\137PNG\r\n\26\n" or head:sub(13, 16) ~= "IHDR" then return nil end
  return u32be(head, 17), u32be(head, 21)
end

--- GIF: "GIF87a"/"GIF89a" and then the logical screen descriptor.
---@param head string at least 10 bytes
---@return integer|nil width, integer|nil height
local function gif(head)
  if #head < 10 or (head:sub(1, 6) ~= "GIF87a" and head:sub(1, 6) ~= "GIF89a") then return nil end
  return u16le(head, 7), u16le(head, 9)
end

--- BMP: the DIB header's width and height. Height is signed — a negative one
--- means the rows are stored top-down, which says nothing about how tall the
--- picture is, so it is the magnitude that matters here.
---@param head string at least 26 bytes
---@return integer|nil width, integer|nil height
local function bmp(head)
  if #head < 26 or head:sub(1, 2) ~= "BM" then return nil end
  local w, h = u32le(head, 19), u32le(head, 23)
  if h >= 0x80000000 then h = 0x100000000 - h end
  return w, h
end

--- WebP: three containers under one RIFF wrapper, and the size sits in a
--- different place with a different encoding in each.
---
--- The length each variant needs is checked per variant rather than once at
--- the top against the longest of them. A lossless header is complete after 25
--- bytes and a whole small file can be shorter than the 30 an extended one
--- wants — a shared bound would answer nil for a file that says exactly what
--- was asked.
---@param head string
---@return integer|nil width, integer|nil height
local function webp(head)
  if #head < 16 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WEBP" then return nil end

  local kind = head:sub(13, 16)

  if kind == "VP8X" then
    -- Extended: canvas size as two 24-bit little-endian values, each minus 1.
    if #head < 30 then return nil end
    local w = head:byte(25) + head:byte(26) * 256 + head:byte(27) * 65536
    local h = head:byte(28) + head:byte(29) * 256 + head:byte(30) * 65536
    return w + 1, h + 1
  end

  if kind == "VP8 " then
    -- Lossy: a 3-byte start code, then 14 bits of width and 14 of height.
    if #head < 30 then return nil end
    if head:byte(24) ~= 0x9D or head:byte(25) ~= 0x01 or head:byte(26) ~= 0x2A then return nil end
    return u16le(head, 27) % 16384, u16le(head, 29) % 16384
  end

  if kind == "VP8L" then
    -- Lossless: a signature byte, then 14 bits of width-1 and 14 of height-1
    -- packed across four bytes.
    if #head < 25 or head:byte(21) ~= 0x2F then return nil end
    local bits = u32le(head, 22)
    return (bits % 16384) + 1, (math.floor(bits / 16384) % 16384) + 1
  end

  return nil
end

--- JPEG: the only one that has to be walked. The size lives in a frame header
--- (SOF0-SOF15, minus the three codes in that range that are something else),
--- and how far in that sits depends on what came before it — an EXIF block
--- with a thumbnail can push it kilobytes down the file. So: hop from segment
--- to segment by their declared lengths, and stop at the start of scan, past
--- which there is no header left to find.
---@param f file* positioned anywhere; this seeks
---@return integer|nil width, integer|nil height
local function jpeg(f)
  f:seek("set", 2)

  -- A bound rather than `while true`: a truncated or hostile file must cost a
  -- fixed number of reads, not an unbounded walk.
  for _ = 1, 512 do
    local marker = f:read(2)
    if not marker or #marker < 2 then return nil end

    local lead, code = marker:byte(1, 2)
    if lead ~= 0xFF then return nil end

    -- Fill bytes: any number of 0xFF may precede the code.
    while code == 0xFF do
      local nxt = f:read(1)
      if not nxt or #nxt < 1 then return nil end
      code = nxt:byte(1)
    end

    -- Start of scan: every header is behind us, and what follows is
    -- entropy-coded data that must not be walked as if it were markers.
    if code == 0xDA then return nil end

    -- Standalone markers carry no length field to skip over; everything else
    -- declares its own.
    if code ~= 0x01 and not (code >= 0xD0 and code <= 0xD9) then
      local raw_len = f:read(2)
      if not raw_len or #raw_len < 2 then return nil end
      local len = u16be(raw_len, 1)
      if len < 2 then return nil end

      local is_sof = code >= 0xC0 and code <= 0xCF and code ~= 0xC4 and code ~= 0xC8 and code ~= 0xCC
      if is_sof then
        -- precision (1 byte), height (2), width (2) -- height first.
        local body = f:read(5)
        if not body or #body < 5 then return nil end
        return u16be(body, 4), u16be(body, 2)
      end

      f:seek("cur", len - 2)
    end
  end

  return nil
end

--- The pixel size of `path`, or nil when this file does not say (SVG, an
--- unknown container, a truncated header, an unreadable file).
---
--- Cheap enough to call on every draw: one `open`, one small read, and a
--- cached answer keyed by the file's own identity from then on.
---@param path string|nil absolute path
---@return Images.Scale.Dims|nil
function M.read(path)
  if type(path) ~= "string" or path == "" then return nil end

  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end

  local key = ("%s:%d:%d"):format(path, stat.mtime and stat.mtime.sec or 0, stat.size)
  local hit = cache[key]
  if hit ~= nil then return hit or nil end

  local f = io.open(path, "rb")
  if not f then
    cache[key] = false
    return nil
  end

  -- 30 bytes covers every fixed-offset container here; JPEG re-seeks anyway.
  local head = f:read(30) or ""

  local w, h
  if head:sub(1, 2) == "\255\216" then
    w, h = jpeg(f)
  else
    w, h = png(head)
    if not w then
      w, h = gif(head)
    end
    if not w then
      w, h = webp(head)
    end
    if not w then
      w, h = bmp(head)
    end
  end

  f:close()

  if not (w and h and w > 0 and h > 0) then
    cache[key] = false
    return nil
  end

  local dims = { width = w, height = h }
  cache[key] = dims
  return dims
end

return M
