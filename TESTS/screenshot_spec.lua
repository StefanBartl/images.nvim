-- TESTS/screenshot_spec.lua — Verfügbarkeitserkennung von `:Image screenshot`.
--
-- Nur `available()`/`unavailable_reason()` sind hier abgedeckt: reine
-- Abfragen von `vim.fn.has`/`executable`, ohne einen echten Aufnahmevorgang
-- auszulösen. Der eigentliche Aufnahmepfad startet ein externes,
-- interaktives Werkzeug (Snipping Tool/screencapture/grim+slurp/maim) und
-- ist damit weder headless noch ohne einen Menschen an der Maus sinnvoll
-- automatisierbar — dieselbe Grenze wie beim echten Download in
-- images.remote, dort ebenfalls nur manuell verifiziert, nicht committet.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local screenshot = require("images.screenshot")

  -- `available()` muss unabhängig vom tatsächlichen Ergebnis fehlerfrei
  -- durchlaufen — auf jeder Plattform, auf der die Suite läuft (hier: die
  -- CI-Plattform bzw. der lokale Rechner), nicht nur der, für die das
  -- konkrete Ergebnis gilt.
  local ok, available = pcall(screenshot.available)
  H.ok(ok, "available() wirft nicht: " .. tostring(available))
  H.ok(type(available) == "boolean", "available() liefert ein boolean")

  if not available then
    local ok2, reason = pcall(screenshot.unavailable_reason)
    H.ok(ok2, "unavailable_reason() wirft nicht: " .. tostring(reason))
    H.ok(type(reason) == "string" and #reason > 0, "…und liefert eine nicht-leere Begründung")
  end

  -- Unter Windows ist immer verfügbar (ms-screenclip: gehört zum System,
  -- kein separates Werkzeug nötig) — der einzige Fall, der sich ohne
  -- Plattform-Mocking eindeutig prüfen lässt.
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    H.ok(available, "unter Windows immer verfügbar (ms-screenclip: braucht kein externes Werkzeug)")
  end
end
