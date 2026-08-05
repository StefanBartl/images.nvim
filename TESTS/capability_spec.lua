-- TESTS/capability_spec.lua — Terminal-Fähigkeitsprüfung.
--
-- Die Erkennung liest nur Umgebungsvariablen, ist also ohne Terminal prüfbar.
-- Geprüft wird vor allem, dass sie *nicht* hart sperrt und dass die Meldung
-- einen brauchbaren nächsten Schritt enthält.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")

  -- Umgebung sichern und am Ende wiederherstellen, damit die Specs
  -- untereinander unabhängig bleiben.
  local saved = {}
  local keys = {
    "WEZTERM_EXECUTABLE",
    "WEZTERM_VERSION",
    "WEZTERM_PANE",
    "TERM_PROGRAM",
    "LC_TERMINAL",
    "KONSOLE_VERSION",
    "TMUX",
  }
  for _, k in ipairs(keys) do
    saved[k] = vim.env[k]
    vim.env[k] = nil
  end

  local function fresh(force)
    terminal.reset_capability()
    return terminal.capability(force)
  end

  -- ── Ohne jede Kennung: nicht erkannt, aber mit Hinweis ─────────────────────
  local cap = fresh(false)
  H.falsy(cap.ok, "unbekanntes Terminal gilt als nicht unterstützt")
  H.ok(cap.reason and #cap.reason > 0, "es gibt eine Begründung")
  H.contains(cap.hint or "", "imgcat", "der Hinweis nennt den konkreten Test")
  H.contains(cap.hint or "", "assume_supported", "…und die Option, die ihn abstellt")

  -- ── force übergeht die Erkennung ───────────────────────────────────────────
  cap = fresh(true)
  H.ok(cap.ok, "assume_supported erklärt das Terminal für tauglich")

  -- ── WezTerm wird an jeder seiner Variablen erkannt ─────────────────────────
  for _, var in ipairs({ "WEZTERM_EXECUTABLE", "WEZTERM_VERSION", "WEZTERM_PANE" }) do
    vim.env[var] = "x"
    cap = fresh(false)
    H.ok(cap.ok, "WezTerm über " .. var .. " erkannt")
    H.eq(cap.terminal, "WezTerm", "…und beim Namen genannt")
    vim.env[var] = nil
  end

  -- ── iTerm2 über beide üblichen Variablen ───────────────────────────────────
  vim.env.TERM_PROGRAM = "iTerm.app"
  cap = fresh(false)
  H.eq(cap.terminal, "iTerm2", "iTerm2 über TERM_PROGRAM")
  vim.env.TERM_PROGRAM = nil

  vim.env.LC_TERMINAL = "iTerm2"
  cap = fresh(false)
  H.eq(cap.terminal, "iTerm2", "iTerm2 über LC_TERMINAL (überlebt SSH)")
  vim.env.LC_TERMINAL = nil

  -- ── tmux ergänzt einen Hinweis, auch bei erkanntem Terminal ────────────────
  vim.env.WEZTERM_PANE = "0"
  vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
  cap = fresh(false)
  H.ok(cap.ok, "tmux macht ein taugliches Terminal nicht untauglich")
  H.contains(cap.hint or "", "allow-passthrough", "…aber der Hinweis nennt die nötige tmux-Option")
  vim.env.TMUX = nil
  vim.env.WEZTERM_PANE = nil

  -- ── Ergebnis wird gemerkt ──────────────────────────────────────────────────
  terminal.reset_capability()
  vim.env.WEZTERM_PANE = "0"
  local first = terminal.capability(false)
  vim.env.WEZTERM_PANE = nil
  local second = terminal.capability(false)
  H.eq(first.terminal, second.terminal, "das Ergebnis wird gemerkt, nicht neu geraten")

  for _, k in ipairs(keys) do
    vim.env[k] = saved[k]
  end
  terminal.reset_capability()
end
