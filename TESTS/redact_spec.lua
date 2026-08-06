-- TESTS/redact_spec.lua — `:Image redact`, nur der sicher prüfbare Teil.
--
-- `M.open()` öffnet ein echtes Fenster und zeichnet (`images.terminal.draw`)
-- — bleibt ungeprüft, wie `images.zen.open()` in zen_spec.lua. Die eigentliche
-- Geometrie (`images.scale.fit_cells`/`cell_box_to_pixels`) und das Brennen
-- (`images.convert.redact`) sind in scale_spec.lua/convert_spec.lua getestet.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local redact = require("images.redact")

  -- ── Kein offenes Fenster: is_open/close sind sichere No-ops ────────────────
  H.falsy(redact.is_open(), "kein Redact-Fenster offen")
  redact.close() -- darf nicht fehlschlagen
  H.falsy(redact.is_open(), "close() bleibt ein No-op ohne offenes Fenster")
end
