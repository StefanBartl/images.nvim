-- TESTS/terminal_draw_spec.lua — Reihenfolge von Repaint und Bildausgabe.
--
-- Die Bildausgabe selbst braucht ein Terminal mit Grafikprotokoll und bleibt
-- headless ungeprüft (siehe run.lua). Prüfbar ist aber die Invariante, an der
-- `:Image zen` einmal gescheitert ist: `nvim_ui_send` schreibt sofort ans
-- Terminal, Neovims eigener Repaint läuft erst beim Rücksprung in die
-- Hauptschleife. Wer ein Fenster öffnet und im selben Tick hineinzeichnet,
-- sendet das Bild und lässt Neovim danach die leeren Zellen dieses Fensters
-- darüber malen — Popup da, Bild weg.
--
-- Dagegen hilft zweierlei, und beides wird hier festgenagelt:
--   1. `terminal.draw` erzwingt den anstehenden Repaint, BEVOR die Payload
--      rausgeht — räumt weg, was vor dem Senden bereits anstand.
--   2. Jeder Pfad, der ein Fenster öffnet (`zen`, `hover_float`, `redact`),
--      zeichnet erst im nächsten Tick — denn den Repaint, den das Öffnen
--      selbst auslöst, kann kein Flush vor dem Senden abfangen.
-- Geprüft wird die Reihenfolge, nicht das Zeichnen.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")

  -- Ohne `nvim_ui_send` (API-Level < 14) gibt es nichts zu ordnen.
  if not terminal.available() then return end

  --- `draw`/`draw_many` mit protokollierten Seiteneffekten ausführen.
  ---@param fn fun()
  ---@return string[] log  "redraw" bzw. "payload", in Aufrufreihenfolge
  local function record(fn)
    local log = {}
    local real_send, real_cmd = vim.api.nvim_ui_send, vim.cmd
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then log[#log + 1] = "payload" end
    end
    vim.cmd = function(c, ...)
      if c == "redraw" then
        log[#log + 1] = "redraw"
        return
      end
      return real_cmd(c, ...)
    end
    local ok, err = pcall(fn)
    vim.api.nvim_ui_send, vim.cmd = real_send, real_cmd
    if not ok then error(err, 0) end
    return log
  end

  -- Eine winzige, aber echte Datei: `draw` liest sie, bevor irgendetwas
  -- gesendet wird — ein nicht lesbarer Pfad würde vor dem Flush aussteigen
  -- und die Reihenfolge gar nicht erst erreichen.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- nicht dekodierbar, aber nicht leer")

    -- ── Einzelbild ──────────────────────────────────────────────────────────
    local log = record(function()
      H.ok(terminal.draw(img, 1, 1, 10, 5), "draw meldet Erfolg für eine lesbare Datei")
    end)
    H.eq(#log, 2, "draw: genau ein Flush und eine Payload")
    H.eq(log[1], "redraw", "draw: Repaint kommt VOR der Payload")
    H.eq(log[2], "payload", "draw: Payload kommt nach dem Repaint")

    -- ── Galerie ─────────────────────────────────────────────────────────────
    log = record(function()
      local drawn = terminal.draw_many({
        { file = img, row = 1, col = 1, cols = 5, rows = 3 },
        { file = img, row = 1, col = 7, cols = 5, rows = 3 },
      })
      H.eq(drawn, 2, "draw_many zeichnet beide Platzierungen")
    end)
    H.eq(log[1], "redraw", "draw_many: Repaint kommt VOR der ersten Payload")
    H.eq(#log, 3, "draw_many: ein Flush für den ganzen Block, nicht pro Bild")

    -- ── Fehlerfall ──────────────────────────────────────────────────────────
    -- Keine Payload, kein Anspruch auf eine bestimmte Flush-Zahl: Hauptsache,
    -- ein unlesbarer Pfad meldet sauber statt zu senden.
    log = record(function()
      local ok = terminal.draw(dir .. "/gibt-es-nicht.png", 1, 1, 10, 5)
      H.falsy(ok, "draw meldet Misserfolg für einen fehlenden Pfad")
    end)
    for _, entry in ipairs(log) do
      H.ok(entry ~= "payload", "fehlende Datei sendet keine Payload")
    end

    -- ── Fenster-Pfade zeichnen erst im nächsten Tick ────────────────────────
    -- Die zweite Hälfte derselben Ursache: der Flush oben räumt weg, was VOR
    -- dem Senden anstand — nicht den Repaint, den das Öffnen des Fensters
    -- selbst auslöst. Wer ein Fenster erzeugt und im selben Tick zeichnet,
    -- liegt weiterhin unter Neovims Farbe. Deshalb muss bei `zen` (und
    -- gleichermaßen `hover_float`/`redact`) NACH dem Aufruf noch nichts
    -- gesendet sein.
    local zen = require("images.zen")
    -- Ohne das meldet der Fähigkeits-Guard im Testlauf berechtigt ein
    -- unerkanntes Terminal — hier nur Rauschen, die Reihenfolge hängt nicht
    -- daran.
    local prev_cfg = require("images.config").get()
    require("images.config").setup({ display = { assume_supported = true } })

    local sent = 0
    local real_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then sent = sent + 1 end
    end
    local ok_open, opened = pcall(zen.open, img)
    local immediate = sent
    vim.wait(500, function()
      return sent > 0
    end)
    local deferred = sent
    vim.api.nvim_ui_send = real_send
    pcall(zen.close)
    require("images.config").setup(prev_cfg)

    H.ok(ok_open and opened, "zen.open öffnet das Fenster")
    H.eq(immediate, 0, "zen zeichnet NICHT im selben Tick wie das Fenster-Öffnen")
    H.eq(deferred, 1, "zen zeichnet genau einmal, sobald der Loop weiterläuft")
  end)
end
