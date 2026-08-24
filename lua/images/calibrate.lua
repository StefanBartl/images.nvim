---@module 'images.calibrate'
---@brief `:Image calibrate` — die Platzierung einmessen, statt sie zu raten.
---@description
--- Ein Terminal kann sein Bild anders platzieren, als `CSI row;col H` es
--- verlangt: WezTerm rechnet sein eigenes `window_padding` bei der
--- OSC-1337-Platzierung nicht mit, andere Terminals mit eigenem Fensterrand
--- vermutlich ebenso (Messprotokoll: docs/ROADMAP/TERMINALS.md). Der Versatz
--- ist aus Neovim heraus **nicht** ermittelbar — `:h TermResponse` reicht
--- keine CSI-Antworten durch, `nvim_list_uis()` kennt keine Pixel. Und er ist
--- auch nicht konstant: derselbe Wert stimmte an einer Cursorposition und war
--- an einer anderen bereits übers Ziel hinaus. Ein Wert in der Doku wäre also
--- schon für ein einzelnes Setup falsch.
---
--- Bleibt: den Menschen fragen, der es sieht.
---
--- **Warum Verschieben und keine Fragen.** Die erste Fassung zeigte eine
--- Testkarte und fragte per Auswahlmenü, was an welcher Kante zu sehen sei.
--- Das konnte nicht funktionieren, aus genau dem Grund, der in
--- `images.anchor` steht: das Menü ist ein Fenster, Neovim malt beim Öffnen
--- über die Zellen — und damit über das Bild, das beurteilt werden sollte.
--- Übrig blieb ein leerer Rahmen und eine Frage dazu.
---
--- Das Verschieben löst beides auf einmal. Es gibt kein zweites Fenster, das
--- etwas verdecken könnte, und jeder Tastendruck zeichnet ohnehin neu — der
--- Repaint, der vorher das Problem war, ist jetzt Teil der Schleife. Vor
--- allem aber muss niemand mehr schätzen: statt "wie viele Zeilen steht es
--- über?" heißt es "schieb, bis es passt". Das ist dieselbe Information, nur
--- ohne den Umweg über eine Zahl, die man am Bildschirm nicht ablesen kann.
---
--- **Was am Ende nicht lösbar bleibt.** Ist der Versatz kleiner als eine
--- Zelle, springt das Bild beim Schieben darüber hinweg, ohne je genau zu
--- sitzen. Der Abschluss sagt das dann und verweist auf
--- `display.draw_inset` — das ist keine Ausrede, sondern die Protokollgrenze,
--- und sie gehört benannt statt kaschiert.

local M = {}

--- Größe des Kalibrierfensters in Zellen, als Anteil der Editorfläche.
--- Groß genug, dass eine Zelle Versatz deutlich sichtbar ist, klein genug,
--- dass ringsum Text stehen bleibt — der Text macht überhaupt erst sichtbar,
--- wo der Fensterrand verläuft.
M.WINDOW = { width = 0.6, height = 0.6 }

---@class Images.Calibrate.State
---@field row integer aktueller Zeilen-Korrekturwert
---@field col integer aktueller Spalten-Korrekturwert
---@field win integer|nil
---@field buf integer|nil
---@field card string|nil Pfad der Testkarte
---@field prev_win integer|nil Fenster, das vor dem Start fokussiert war

---@type Images.Calibrate.State|nil
local state = nil

---@internal
--- Dasselbe Muster wie in `images.redact` und den übrigen Modulen:
--- `lib.nvim.notify` ist eine Fabrik, kein fertiger Notifier.
---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@internal
--- Testkarte mit den aktuellen Korrekturwerten neu zeichnen.
---
--- `padding` geht als Aufruf-Option mit, nicht über `images.config`: ein
--- Wert, den der User gerade durchprobiert, ist keine Einstellung, und eine
--- Kalibrierung, die unterwegs die laufende Konfiguration umschreibt, wäre
--- schlimmer als das Problem, das sie löst.
---
--- `inset = 0`, weil hier die Kante des Bildes die Kante des Fensters treffen
--- soll — eine Marge würde genau das verdecken, was beurteilt wird.
---@return nil
local function redraw()
  if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  require("images.anchor").draw(state.win, "full", state.card, {
    defer = true,
    inset = 0,
    padding = { row = state.row, col = state.col },
  })
end

---@internal
--- Fenster schließen, Testkarte löschen, Fokus zurückgeben.
---@return nil
local function teardown()
  if not state then return end
  local prev = state.prev_win
  local card = state.card
  local win = state.win
  state = nil

  pcall(function()
    require("images.terminal").clear()
  end)
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  if prev and vim.api.nvim_win_is_valid(prev) then pcall(vim.api.nvim_set_current_win, prev) end
  if card then pcall(os.remove, card) end
end

---@internal
--- Ergebnis mitteilen und das Speichern anbieten.
---@param row integer
---@param col integer
---@return nil
local function offer_save(row, col)
  if row == 0 and col == 0 then
    notify().info("Nichts zu speichern — die Platzierung sitzt bereits ohne Korrektur.")
    return
  end

  local summary = ("terminal_padding = { row = %d, col = %d }"):format(row, col)

  local function persist()
    local ok, err = require("images.calibration").save({ terminal_padding = { row = row, col = col } })
    if ok then
      notify().info("Gespeichert (" .. summary .. ").\nGilt ab sofort und nach jedem Neustart.")
      require("images.config").setup({ display = { terminal_padding = { row = row, col = col } } })
    else
      notify().error("Speichern fehlgeschlagen: " .. tostring(err))
    end
  end

  local function decline()
    notify().info("Nicht gespeichert. Für die eigene setup()-Spec:\ndisplay = { " .. summary .. " }")
  end

  local ok_confirm, confirm = pcall(require, "lib.nvim.ui.kit.confirm")
  if ok_confirm and type(confirm.open) == "function" then
    confirm.open({
      question = "Kalibrierung übernehmen?\n" .. summary,
      on_answer = function(answer)
        if answer == true then
          persist()
        else
          decline()
        end
      end,
    })
    return
  end

  vim.ui.select({ "Ja, speichern", "Nein, nur anzeigen" }, { prompt = "Kalibrierung übernehmen? " .. summary }, function(_, idx)
    if idx == 1 then
      persist()
    else
      decline()
    end
  end)
end

---@internal
--- Die Tasten des Kalibrierfensters. Bewusst beides — Pfeile für den ersten
--- Versuch, `hjkl` für die Finger, die schon wissen, wo sie hingreifen.
---@param buf integer
---@return nil
local function set_keymaps(buf)
  local function nudge(d_row, d_col)
    return function()
      if not state then return end
      state.row = state.row + d_row
      state.col = state.col + d_col
      -- Titel mitführen: der aktuelle Wert soll ablesbar sein, ohne dass man
      -- die Tastendrücke im Kopf mitzählt.
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        pcall(vim.api.nvim_win_set_config, state.win, {
          title = (" Kalibrierung   row %d   col %d   ⏎ übernehmen   q abbrechen "):format(state.row, state.col),
        })
      end
      redraw()
    end
  end

  local map = vim.keymap.set
  local o = { buffer = buf, nowait = true, silent = true }

  for _, k in ipairs({ "k", "<Up>" }) do
    map("n", k, nudge(-1, 0), vim.tbl_extend("force", o, { desc = "images.calibrate: Bild nach oben" }))
  end
  for _, k in ipairs({ "j", "<Down>" }) do
    map("n", k, nudge(1, 0), vim.tbl_extend("force", o, { desc = "images.calibrate: Bild nach unten" }))
  end
  for _, k in ipairs({ "h", "<Left>" }) do
    map("n", k, nudge(0, -1), vim.tbl_extend("force", o, { desc = "images.calibrate: Bild nach links" }))
  end
  for _, k in ipairs({ "l", "<Right>" }) do
    map("n", k, nudge(0, 1), vim.tbl_extend("force", o, { desc = "images.calibrate: Bild nach rechts" }))
  end

  map("n", "r", function()
    if not state then return end
    state.row, state.col = 0, 0
    redraw()
  end, vim.tbl_extend("force", o, { desc = "images.calibrate: zurücksetzen" }))

  map("n", "<CR>", function()
    if not state then return end
    local row, col = state.row, state.col
    teardown()
    -- Erst nach dem Schließen fragen: solange das Bild noch steht, würde der
    -- Dialog darüber malen (siehe Moduldoku).
    vim.schedule(function()
      offer_save(row, col)
    end)
  end, vim.tbl_extend("force", o, { desc = "images.calibrate: übernehmen" }))

  for _, k in ipairs({ "q", "<Esc>" }) do
    map("n", k, function()
      teardown()
      notify().info("Kalibrierung abgebrochen")
    end, vim.tbl_extend("force", o, { desc = "images.calibrate: abbrechen" }))
  end
end

--- Die Kalibrierung starten.
---@return boolean started
function M.run()
  if state then
    notify().warn("Es läuft bereits eine Kalibrierung")
    return false
  end

  local display = require("images.config").get().display
  local cap = require("images.terminal").capability(display.assume_supported)
  if not cap.ok then
    notify().error(cap.reason or "Terminal kann keine Bilder zeichnen")
    return false
  end

  local cols = math.max(20, math.floor(vim.o.columns * M.WINDOW.width))
  local rows = math.max(8, math.floor(vim.o.lines * M.WINDOW.height))

  local card, card_err = require("images.testcard").write(cols, rows, require("images.scale").CELL_ASPECT)
  if not card then
    notify().error(card_err or "Testkarte konnte nicht erzeugt werden")
    return false
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local blank = {}
  for i = 1, rows do
    blank[i] = ""
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, blank)
  vim.bo[buf].modifiable = false

  local current = display.terminal_padding or {}
  local start_row = type(current.row) == "number" and current.row or 0
  local start_col = type(current.col) == "number" and current.col or 0

  local prev_win = vim.api.nvim_get_current_win()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - rows) / 2),
    col = math.floor((vim.o.columns - cols) / 2),
    width = cols,
    height = rows,
    style = "minimal",
    border = "rounded",
    noautocmd = true,
    title = (" Kalibrierung   row %d   col %d   ⏎ übernehmen   q abbrechen "):format(start_row, start_col),
  })

  state = { row = start_row, col = start_col, win = win, buf = buf, card = card, prev_win = prev_win }

  set_keymaps(buf)
  redraw()

  notify().info(
    "Schieb die Testkarte mit hjkl / Pfeiltasten, bis ihr Rahmen genau\n"
      .. "am Fensterrand sitzt. r setzt zurück, ⏎ übernimmt, q bricht ab.\n"
      .. "Springt sie über die richtige Stelle hinweg, ist der Rest kleiner\n"
      .. "als eine Zelle — dann hilft nur display.draw_inset."
  )

  return true
end

--- Eine laufende Kalibrierung abbrechen.
---@return nil
function M.cancel()
  teardown()
end

return M
