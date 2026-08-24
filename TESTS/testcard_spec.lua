-- TESTS/testcard_spec.lua — der eigene PNG-Schreiber.
--
-- Ohne externe Werkzeuge ein gültiges PNG zu bauen ist genau die Sorte Code,
-- die still falsch sein kann: ein Header, den jeder Parser akzeptiert, mit
-- einer Prüfsumme, an der jeder Decoder aussteigt. Genau daran ist die erste
-- Fassung gescheitert (LuaJIT rechnet Bit-Operationen vorzeichenbehaftet, die
-- Division-als-Schieben-Variante lieferte falsche CRCs). Deshalb wird hier
-- die Struktur nachgerechnet, nicht nur "sieht aus wie ein PNG" geprüft.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local testcard = require("images.testcard")

  ---@param s string
  ---@param off integer 1-basiert
  ---@return integer
  local function be32_at(s, off)
    return s:byte(off) * 0x1000000 + s:byte(off + 1) * 0x10000 + s:byte(off + 2) * 0x100 + s:byte(off + 3)
  end

  -- ── size_for: die Karte übernimmt das Seitenverhältnis der Zellbox ────────
  -- Der ganze Zweck des Moduls. Stimmt das nicht, letterboxt das Terminal und
  -- die Kalibrierung misst den Letterbox-Rand statt der Platzierung.
  local size = testcard.size_for(60, 20, 0.46)
  local want = (60 * 0.46) / 20
  local got = size.width / size.height
  H.ok(math.abs(got - want) < 0.01, ("size_for trifft das Box-Seitenverhältnis (%.4f ≈ %.4f)"):format(got, want))
  H.ok(math.max(size.width, size.height) <= testcard.LONG_EDGE, "…und bleibt innerhalb LONG_EDGE")

  -- Eine sehr hohe Box: die lange Kante ist dann die Höhe, nicht die Breite.
  local tall = testcard.size_for(10, 40, 0.5)
  H.ok(tall.height >= tall.width, "hohe Box ergibt eine hohe Karte")
  H.ok(math.max(tall.width, tall.height) <= testcard.LONG_EDGE, "…ebenfalls innerhalb LONG_EDGE")

  -- Entartete Eingaben dürfen keine 0-Pixel-Kante erzeugen: OSC 1337 würde
  -- eine leere Datei senden und das Terminal nichts zeichnen.
  local tiny = testcard.size_for(1, 1, 0.5)
  H.ok(tiny.width >= 8 and tiny.height >= 8, "winzige Box ergibt trotzdem eine zeichenbare Karte")

  -- ── build: PNG-Struktur ───────────────────────────────────────────────────
  local png = testcard.build(64, 32)
  H.eq(png:sub(1, 8), "\137PNG\r\n\26\n", "PNG-Signatur stimmt")

  -- Chunk-Kette ablaufen und dabei prüfen, dass die Längenfelder konsistent
  -- sind — ein zu kurzes/langes Feld läuft hier in einen Fehlschlag statt
  -- erst im Decoder des Terminals.
  local seen, off = {}, 9
  while off < #png do
    local len = be32_at(png, off)
    local kind = png:sub(off + 4, off + 7)
    seen[#seen + 1] = kind
    off = off + 12 + len
  end
  H.eq(off, #png + 1, "die Chunk-Längen summieren sich exakt auf die Dateigröße")
  H.eq(seen[1], "IHDR", "erster Chunk ist IHDR")
  H.eq(seen[#seen], "IEND", "letzter Chunk ist IEND")
  H.ok(vim.tbl_contains(seen, "IDAT"), "es gibt einen IDAT-Chunk")

  -- IHDR-Inhalt: Maße und Farbtyp, so wie der Aufrufer sie bestellt hat.
  H.eq(be32_at(png, 17), 64, "IHDR meldet die bestellte Breite")
  H.eq(be32_at(png, 21), 32, "IHDR meldet die bestellte Höhe")
  H.eq(png:byte(25), 8, "Bittiefe 8")
  H.eq(png:byte(26), 2, "Farbtyp 2 (RGB ohne Alpha)")

  -- ── CRC: der Fehler, an dem die erste Fassung scheiterte ──────────────────
  -- Gegen `vim.zlib`/`vim.uv` gibt es keine CRC-32-Funktion in Neovim, also
  -- wird hier eine unabhängige Referenzimplementierung gerechnet — bewusst
  -- anders geschrieben als die im Modul (Tabelle pro Aufruf, keine
  -- Zwischenspeicherung), damit ein gemeinsamer Denkfehler nicht beide
  -- gleichzeitig falsch macht.
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
    local body = png:sub(pos + 4, pos + 7 + len) -- Typ + Nutzdaten
    local stored = be32_at(png, pos + 8 + len)
    H.eq(stored, reference_crc32(body), ("CRC von %s stimmt"):format(png:sub(pos + 4, pos + 7)))
    checked = checked + 1
    pos = pos + 12 + len
  end
  H.ok(checked >= 3, "alle Chunks wurden geprüft (IHDR/IDAT/IEND)")

  -- ── IDAT: zlib-Rahmen und Rohdatenlänge ──────────────────────────────────
  -- Der Strom besteht aus *stored*-Blöcken; die entpackte Größe muss exakt
  -- `höhe * (1 + breite * 3)` sein (je Zeile ein Filterbyte plus RGB).
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
  H.ok(idat_pos ~= nil, "IDAT gefunden")

  local idat = png:sub(idat_pos, idat_pos + idat_len - 1)
  H.eq(idat:byte(1), 0x78, "zlib-Header CMF = 0x78")

  -- Stored-Blöcke ablaufen: Kopf (1 Byte), LEN, NLEN, Daten. LEN und NLEN
  -- müssen einander zu 0xFFFF ergänzen, sonst weist jeder Decoder den Strom
  -- zurück. Start bei 3: davor liegen die zwei zlib-Kopfbytes (CMF/FLG).
  local p, payload, final = 3, 0, 0
  while p < idat_len do
    final = idat:byte(p)
    local blen = idat:byte(p + 1) + idat:byte(p + 2) * 256
    local nlen = idat:byte(p + 3) + idat:byte(p + 4) * 256
    H.eq(blen + nlen, 0xFFFF, "LEN und NLEN ergänzen sich zu 0xFFFF")
    payload = payload + blen
    p = p + 5 + blen
    if final == 1 then break end
  end
  H.eq(final, 1, "der letzte Block ist als final markiert")
  H.eq(payload, 32 * (1 + 64 * 3), "entpackte Größe = höhe * (1 + breite * 3)")
  H.eq(p + 4, idat_len + 1, "nach dem letzten Block folgen genau 4 Byte Adler-32")
end
