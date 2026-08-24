-- TESTS/anchor_spec.lua — die kanonische "Bild in einem Fenster zeichnen"-Stelle.
--
-- `resolve_window` ist mit echten Fenstern/Buffern ohne Terminal prüfbar.
-- Das eigentliche Zeichnen braucht ein Grafikprotokoll und bleibt ungeprüft
-- (siehe run.lua) — geprüft wird stattdessen dieselbe Invariante wie in
-- terminal_draw_spec.lua: ob und wann `nvim_ui_send` überhaupt aufgerufen
-- wird, per Mock, nicht das tatsächliche Zeichnen.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local anchor = require("images.anchor")

  -- ── resolve_window: nil/0 → aktuelles Fenster ──────────────────────────────
  local current = vim.api.nvim_get_current_win()
  H.eq(anchor.resolve_window(nil), current, "nil löst auf das aktuelle Fenster auf")
  H.eq(anchor.resolve_window(0), current, "0 löst auf das aktuelle Fenster auf")

  -- ── resolve_window: ein valides Fenster-Handle bleibt unverändert ─────────
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  local other_win = vim.api.nvim_open_win(scratch_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 10,
    height = 5,
  })
  H.eq(anchor.resolve_window(other_win), other_win, "ein valides Fenster-Handle bleibt unverändert")

  -- ── resolve_window: Buffer, den das aktuelle Fenster zeigt ────────────────
  local cur_buf = vim.api.nvim_win_get_buf(current)
  H.eq(anchor.resolve_window(cur_buf), current, "Buffer des aktuellen Fensters löst auf dieses auf")

  -- ── resolve_window: Buffer, den nur ein ANDERES Fenster zeigt ─────────────
  H.eq(anchor.resolve_window(scratch_buf), other_win, "Buffer eines anderen Fensters löst auf jenes auf")

  -- ── resolve_window: Buffer ohne irgendein Fenster ──────────────────────────
  local orphan_buf = vim.api.nvim_create_buf(false, true)
  local win2, err2 = anchor.resolve_window(orphan_buf)
  H.eq(win2, nil, "Buffer ohne Fenster liefert kein Ergebnis")
  H.contains(err2 or "", tostring(orphan_buf), "…die Fehlermeldung nennt den Buffer")

  -- ── resolve_window: weder Fenster noch Buffer ──────────────────────────────
  local win3, err3 = anchor.resolve_window(999999)
  H.eq(win3, nil, "ungültiges Handle liefert kein Ergebnis")
  H.ok(err3 ~= nil, "…mit einer Fehlermeldung")

  pcall(vim.api.nvim_win_close, other_win, true)
  pcall(vim.api.nvim_buf_delete, scratch_buf, { force = true })
  pcall(vim.api.nvim_buf_delete, orphan_buf, { force = true })

  -- Ohne `nvim_ui_send` (API-Level < 14) gibt es nichts zu zählen — dieselbe
  -- Zurückhaltung wie terminal_draw_spec.lua.
  if not require("images.terminal").available() then return end

  -- ── draw(): unbekannte Position schlägt fehl, ohne zu zeichnen ────────────
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- nicht dekodierbar, aber nicht leer")

    local sent = 0
    local real_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then sent = sent + 1 end
    end

    local done_ok, done_err
    local ok, err = anchor.draw(nil, "nowhere", img, {
      on_done = function(o, e)
        done_ok, done_err = o, e
      end,
    })
    H.falsy(ok, "unbekannte Position meldet Misserfolg")
    H.ok(err ~= nil, "…mit einer Fehlermeldung")
    H.eq(sent, 0, "…und sendet nichts")
    H.eq(done_ok, false, "on_done läuft synchron mit demselben Ergebnis")
    H.eq(done_err, err, "…und derselben Fehlermeldung")

    -- ── draw(): ohne defer wird sofort gesendet ───────────────────────────────
    sent = 0
    ok = anchor.draw(nil, "full", img)
    H.ok(ok, "draw ohne defer meldet Erfolg für eine lesbare Datei")
    H.eq(sent, 1, "…und sendet sofort, ohne auf den nächsten Tick zu warten")

    -- ── draw(): mit defer wird erst im nächsten Tick gesendet ────────────────
    sent = 0
    done_ok = nil
    local accepted = anchor.draw(nil, "full", img, {
      defer = true,
      on_done = function(o)
        done_ok = o
      end,
    })
    H.ok(accepted, "defer=true meldet sofort 'angenommen'")
    H.eq(sent, 0, "…aber sendet noch nichts im selben Tick")
    vim.wait(500, function()
      return sent > 0
    end)
    H.eq(sent, 1, "…sondern erst, sobald der Loop weiterläuft")
    H.eq(done_ok, true, "on_done meldet danach Erfolg")

    vim.api.nvim_ui_send = real_send
    require("images.terminal").clear()
  end)

  -- ── draw(): Rahmen schiebt die Zeichenposition ein, nicht die Größe ──────
  -- Regressionstest für den Versatz, den ein gerahmtes Hover-Float zeigte:
  -- `nvim_win_get_position` bleibt bei einem Rahmen unverändert (weiterhin
  -- die Rahmen-AUSSENKANTE), also muss `draw_now` selbst um ein Rahmensegment
  -- einrücken. Geprüft über die tatsächlich an `images.terminal.draw`
  -- übergebenen Koordinaten, nicht über die gesendeten Bytes — die Werte
  -- sind hier das Interessante, nicht das Protokoll selbst.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- nicht dekodierbar, aber nicht leer")

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "", "", "", "", "" })

    ---@param border string|table
    ---@return { row: integer, col: integer }
    local function draw_into(border)
      local win = vim.api.nvim_open_win(scratch, false, {
        relative = "editor",
        row = 10,
        col = 10,
        width = 10,
        height = 5,
        style = "minimal",
        border = border,
        focusable = false,
        noautocmd = true,
      })

      local captured
      local real_draw = require("images.terminal").draw
      require("images.terminal").draw = function(_file, row, col, cols, rows)
        captured = { row = row, col = col, cols = cols, rows = rows }
        return true
      end

      anchor.draw(win, "full", img)
      require("images.terminal").draw = real_draw
      vim.api.nvim_win_close(win, true)
      return captured
    end

    local none = draw_into("none")
    H.eq(none.row, 11, "ohne Rahmen: row = pos+1, kein Versatz")
    H.eq(none.col, 11, "ohne Rahmen: col = pos+1, kein Versatz")

    local rounded = draw_into("rounded")
    H.eq(rounded.row, 12, "rounded: row zusätzlich um das obere Rahmensegment eingerückt")
    H.eq(rounded.col, 12, "rounded: col zusätzlich um das linke Rahmensegment eingerückt")

    local top_only = draw_into({ "", "-", "", "", "", "", "", "" })
    H.eq(top_only.row, 12, "nur oberer Rahmen: row rückt ein")
    H.eq(top_only.col, 11, "nur oberer Rahmen: col bleibt unverändert (kein linkes Segment)")

    vim.api.nvim_buf_delete(scratch, { force = true })
  end)
end
