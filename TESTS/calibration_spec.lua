-- TESTS/calibration_spec.lua — gespeicherte Kalibrierwerte und ihre Rangfolge.
--
-- Der interaktive Teil (`images.calibrate`) ist ein Dialog und bleibt hier
-- ungeprüft. Prüfbar — und wichtiger — ist, was danach passiert: dass ein
-- gemessener Wert Neustarts übersteht, dass eine explizite setup()-Option ihn
-- weiterhin überstimmt, und dass eine kaputte Zustandsdatei setup() nicht
-- mitreißt.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local calibration = require("images.calibration")
  local config = require("images.config")

  -- Die echte Zustandsdatei des Users darf ein Testlauf nicht anfassen.
  local real_path = calibration.path
  local sandbox = vim.fn.tempname() .. "-calibration.json"
  calibration.path = function()
    return sandbox
  end

  local function reset()
    pcall(os.remove, sandbox)
    calibration.load(true)
  end

  reset()

  -- ── Ohne Datei: leer, und alles verhält sich wie ohne das Modul ──────────
  H.eq(vim.tbl_count(calibration.load(true)), 0, "ohne Datei sind keine Werte gespeichert")
  H.eq(vim.tbl_count(calibration.as_config()), 0, "…und as_config liefert nichts zum Überlagern")

  -- ── Speichern und wieder lesen ────────────────────────────────────────────
  local ok, err = calibration.save({ terminal_padding = { row = -2, col = 1 } })
  H.ok(ok, "save meldet Erfolg" .. (err and (" (" .. tostring(err) .. ")") or ""))

  local loaded = calibration.load(true)
  H.eq(loaded.terminal_padding and loaded.terminal_padding.row, -2, "row überlebt den Roundtrip")
  H.eq(loaded.terminal_padding and loaded.terminal_padding.col, 1, "col überlebt den Roundtrip")

  local as_cfg = calibration.as_config()
  H.eq(as_cfg.display and as_cfg.display.terminal_padding.row, -2, "as_config verpackt unter `display`")

  -- ── Speichern ergänzt, statt Vorhandenes zu verwerfen ────────────────────
  -- Eine Teilkalibrierung (nur cell_aspect) darf eine frühere vollständige
  -- nicht auslöschen.
  H.ok(calibration.save({ cell_aspect = 0.46 }), "zweiter save meldet Erfolg")
  loaded = calibration.load(true)
  H.eq(loaded.cell_aspect, 0.46, "der neue Wert ist da")
  H.eq(loaded.terminal_padding and loaded.terminal_padding.row, -2, "…und der alte steht noch")

  -- ── Rangfolge: Defaults < Kalibrierung < explizite Optionen ──────────────
  local conf = config.setup({})
  H.eq(conf.display.terminal_padding.row, -2, "ohne eigene Option gilt der gemessene Wert")
  H.eq(conf.display.cell_aspect, 0.46, "…für jeden gespeicherten Schlüssel")

  conf = config.setup({ display = { terminal_padding = { row = 5 } } })
  H.eq(conf.display.terminal_padding.row, 5, "eine explizite setup()-Option überstimmt die Messung")
  H.eq(conf.display.terminal_padding.col, 1, "…ohne die nicht gesetzten Schlüssel mitzureißen")

  -- Defaults bleiben für alles erhalten, was weder gemessen noch gesetzt ist.
  H.eq(conf.display.max_cols, require("images.config.DEFAULTS").display.max_cols, "unberührte Defaults überleben")

  -- ── Eine kaputte Datei darf setup() nicht mitreißen ──────────────────────
  local f = io.open(sandbox, "w")
  f:write("{ das ist kein json")
  f:close()
  calibration.load(true)

  local ok_setup, conf2 = pcall(config.setup, {})
  H.ok(ok_setup, "setup() überlebt eine unlesbare Zustandsdatei")
  H.eq(
    ok_setup and conf2.display.max_cols,
    require("images.config.DEFAULTS").display.max_cols,
    "…und liefert weiterhin die Defaults"
  )

  -- ── clear ─────────────────────────────────────────────────────────────────
  calibration.save({ terminal_padding = { row = -3 } })
  calibration.clear()
  H.eq(vim.tbl_count(calibration.load(true)), 0, "clear entfernt die gespeicherten Werte")

  -- Aufräumen: Sandbox weg, echte Pfadfunktion zurück, Konfiguration neutral.
  pcall(os.remove, sandbox)
  calibration.path = real_path
  calibration.load(true)
  config.setup({})
end
