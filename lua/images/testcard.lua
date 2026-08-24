---@module 'images.testcard'
---@brief Eine Testkarte als PNG erzeugen, ohne externe Werkzeuge.
---@description
--- `images.calibrate` braucht ein Bild, dessen Ränder mit der Zeichenbox
--- zusammenfallen — nur dann heißt "das Bild steht oben über" auch wirklich
--- "die Platzierung sitzt zu tief" und nicht "das Seitenverhältnis passt
--- nicht". Ein mitgeliefertes PNG kann das nicht leisten: die Box hängt von
--- `display.cell_aspect` und der Fenstergröße ab, ist also erst zur Laufzeit
--- bekannt. Deshalb wird die Karte hier gebaut, mit genau dem
--- Pixel-Seitenverhältnis, das die aktuelle Box in Pixeln hat — das Terminal
--- hat dann bei `preserveAspectRatio=1` nichts mehr zu letterboxen.
---
--- **Warum ein eigener PNG-Schreiber statt ImageMagick.** Kalibrierung muss
--- gerade dort funktionieren, wo noch nichts eingerichtet ist; eine
--- Abhängigkeit, die man erst installieren muss, wäre an dieser Stelle die
--- falsche Hürde (siehe die "ImageMagick verbessert, ermöglicht aber nicht"-
--- Leitplanke in docs/ROADMAP/README.md). PNG lässt sich ohne Kompression
--- schreiben: der zlib-Strom darf aus *stored*-Blöcken bestehen, damit
--- braucht es nur CRC-32 und Adler-32, beide wenige Zeilen. Die Datei wird
--- dadurch groß, aber sie lebt nur für die Dauer einer Kalibrierung.

local M = {}

--- Kantenlänge der erzeugten Karte in Pixeln (die längere Achse). Klein
--- genug, dass der unkomprimierte Strom handlich bleibt, groß genug für
--- scharfe Kanten nach der Skalierung durchs Terminal.
M.LONG_EDGE = 480

---@type integer[]|nil
local crc_table = nil

---@internal
--- Durchgängig `bit.*` statt Division: LuaJIT rechnet Bit-Operationen auf
--- *vorzeichenbehafteten* 32-Bit-Werten, alles ab 0x80000000 kommt also
--- negativ zurück. Ein `math.floor(c / 2)` auf so einem Wert schiebt dann in
--- die falsche Richtung und die Prüfsumme ist still falsch — ein PNG, das
--- jeder Header-Parser akzeptiert und kein Decoder liest. `bit.rshift`
--- schiebt logisch und hat das Problem nicht.
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
--- Ein zlib-Strom ohne Kompression: Header, *stored*-Blöcke, Adler-32.
---@param raw string
---@return string
local function zlib_stored(raw)
  local parts = { "\120\001" } -- CMF/FLG für "deflate, kein Preset"

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
---@field width integer Pixel
---@field height integer Pixel

--- Pixelmaße für eine Zellbox bestimmen, so dass das Bild sie exakt ausfüllt.
--- Genau hier steckt der Zweck des Moduls: die Karte übernimmt das
--- Seitenverhältnis der Box, statt dass die Box sich nach der Karte richtet.
---@param cols integer Breite der Zeichenbox in Zellen
---@param rows integer Höhe der Zeichenbox in Zellen
---@param cell_aspect number Breite/Höhe einer Zelle
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

--- Eine Testkarte als PNG-Bytes bauen.
---
--- Das Muster ist auf genau eine Frage hin entworfen: "berührt der Rand des
--- Bildes den Rand des Fensters?". Deshalb ein kräftiger, geschlossener
--- Rahmen direkt an der Kante und je ein Eckblock in einer anderen Farbe —
--- fehlt an einer Seite ein Stück Rahmen, ist es dort abgeschnitten; ist
--- zwischen Rahmen und Fensterrand eine Lücke, sitzt das Bild zu weit innen.
--- Die Mittelkreuze geben zusätzlich einen Anhaltspunkt für "wie viel", weil
--- sie die Fläche in sichtbare Viertel teilen.
---@param width integer Pixel
---@param height integer Pixel
---@return string png Rohe Dateibytes
function M.build(width, height)
  width, height = math.max(8, width), math.max(8, height)

  -- Rahmenstärke: sichtbar, aber nie mehr als ein Achtel der kurzen Kante,
  -- damit das Muster auch bei einer sehr schmalen Box lesbar bleibt.
  local border = math.max(2, math.floor(math.min(width, height) / 24))
  local corner = math.max(border * 3, math.floor(math.min(width, height) / 6))

  local BG = { 0x12, 0x14, 0x1A }
  local FRAME = { 0xE6, 0xB4, 0x50 } -- warm, hebt sich von jedem Theme ab
  local CORNER = { 0x4F, 0xC3, 0xF7 }
  local CROSS = { 0x55, 0x5A, 0x66 }

  local rows_out = {}
  for y = 0, height - 1 do
    local line = { "\0" } -- Filter "None"
    for x = 0, width - 1 do
      local c = BG

      local near_v = x < border or x >= width - border
      local near_h = y < border or y >= height - border
      if near_v or near_h then
        c = FRAME
        -- Ecken abweichend einfärben: sie verraten, WELCHE Kante fehlt, wenn
        -- nur ein Teil des Bildes abgeschnitten ist.
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

--- Eine Testkarte für `cols`x`rows` in eine temporäre Datei schreiben.
---@param cols integer
---@param rows integer
---@param cell_aspect number
---@return string|nil path
---@return string|nil err
function M.write(cols, rows, cell_aspect)
  local size = M.size_for(cols, rows, cell_aspect)
  local ok, png = pcall(M.build, size.width, size.height)
  if not ok then return nil, "Testkarte konnte nicht erzeugt werden: " .. tostring(png) end

  local path = vim.fn.tempname() .. "-images-testcard.png"
  local f, ferr = io.open(path, "wb")
  if not f then return nil, "Testkarte nicht schreibbar: " .. tostring(ferr) end
  f:write(png)
  f:close()
  return path
end

return M
