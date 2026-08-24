---@module 'images.calibrate'
---@brief `:Image calibrate` — die Platzierung einmessen, statt sie zu raten.
---@description
--- Ein Terminal kann sein Bild anders platzieren, als `CSI row;col H` es
--- verlangt: WezTerm rechnet sein eigenes `window_padding` bei der
--- OSC-1337-Platzierung nicht mit, andere Terminals mit eigenem Fensterrand
--- vermutlich ebenso (Messprotokoll: docs/ROADMAP/TERMINALS.md). Der Versatz
--- ist aus Neovim heraus **nicht** ermittelbar — `:h TermResponse` reicht
--- keine CSI-Antworten durch, `nvim_list_uis()` kennt keine Pixel.
---
--- Bleibt: den Menschen fragen, der es sieht. Genau das ist dieses Modul —
--- kein Messgerät, sondern ein Dialog, der die eine Information einsammelt,
--- die der Rechner nicht hat, und daraus die Werte ableitet.
---
--- **Warum in Textzeilen gefragt wird und nicht in Pixeln.** Niemand kann am
--- Bildschirm Pixel abzählen. Zeilen und Spalten dagegen liegen sichtbar
--- daneben — und sie sind zufällig genau die Einheit, in der `CSI row;col H`
--- rechnet. Die Antwort des Users ist damit direkt der Korrekturwert, ohne
--- Umrechnung und ohne Schätzung dazwischen.
---
--- **Warum die Testkarte erzeugt und nicht mitgeliefert wird.** Sie muss das
--- Seitenverhältnis der Zeichenbox exakt treffen, sonst letterboxt das
--- Terminal und der entstehende Rand wäre von einem Platzierungsfehler nicht
--- zu unterscheiden. Siehe `images.testcard`.
---
--- **Was am Ende nicht lösbar bleibt.** Ist der Versatz kleiner als eine
--- Zelle, kann kein Zeilen-/Spaltenwert ihn ausgleichen. Der Dialog sagt das
--- dann und empfiehlt `display.draw_inset` — das ist keine Ausrede, sondern
--- die Protokollgrenze, und sie gehört benannt statt kaschiert.

local M = {}

--- Größe des Kalibrierfensters in Zellen, als Anteil der Editorfläche.
--- Groß genug, dass eine Zelle Versatz deutlich sichtbar ist, klein genug,
--- dass ringsum Text stehen bleibt — der Text ist die Referenz, an der der
--- User "eine Zeile" überhaupt abschätzen kann.
M.WINDOW = { width = 0.6, height = 0.6 }

---@class Images.Calibrate.State
---@field row integer aktueller Zeilen-Korrekturwert
---@field col integer aktueller Spalten-Korrekturwert
---@field residual_row boolean Rest unterhalb einer Zelle, vertikal
---@field residual_col boolean Rest unterhalb einer Zelle, horizontal
---@field win integer|nil
---@field buf integer|nil
---@field card string|nil Pfad der Testkarte
---@field cols integer
---@field rows integer

---@type Images.Calibrate.State|nil
local state = nil

---@internal
---@return table
local function notify()
  local ok, n = pcall(require, "lib.nvim.notify")
  if ok then return n end
  return {
    info = function(m)
      vim.notify(m, vim.log.levels.INFO)
    end,
    warn = function(m)
      vim.notify(m, vim.log.levels.WARN)
    end,
    error = function(m)
      vim.notify(m, vim.log.levels.ERROR)
    end,
  }
end

---@internal
--- `lib.nvim`s UI-Kit, wenn vorhanden. Ohne es bleibt `vim.ui.select`, damit
--- der Befehl auch in einer Installation ohne UI-Kit benutzbar ist.
---@param opts { title: string, items: string[], on_select: fun(item: string, idx: integer), on_cancel: fun() }
local function choose(opts)
  local ok, select = pcall(require, "lib.nvim.ui.kit.select")
  if ok and type(select.open) == "function" then
    select.open({
      title = opts.title,
      items = opts.items,
      on_select = function(item, idx)
        opts.on_select(item, idx)
      end,
      on_cancel = opts.on_cancel,
    })
    return
  end

  vim.ui.select(opts.items, { prompt = opts.title }, function(item, idx)
    if item then
      opts.on_select(item, idx)
    else
      opts.on_cancel()
    end
  end)
end

---@internal
---@param question string
---@param on_answer fun(yes: boolean)
local function ask_yes_no(question, on_answer)
  local ok, confirm = pcall(require, "lib.nvim.ui.kit.confirm")
  if ok and type(confirm.open) == "function" then
    confirm.open({
      question = question,
      on_answer = function(a)
        on_answer(a == true)
      end,
    })
    return
  end

  choose({
    title = question,
    items = { "Ja", "Nein" },
    on_select = function(_, idx)
      on_answer(idx == 1)
    end,
    on_cancel = function()
      on_answer(false)
    end,
  })
end

---@internal
--- Das Kalibrierfenster schließen und die Testkarte wegräumen.
---@return nil
local function teardown()
  if not state then return end
  pcall(function()
    require("images.terminal").clear()
  end)
  if state.win and vim.api.nvim_win_is_valid(state.win) then pcall(vim.api.nvim_win_close, state.win, true) end
  if state.card then pcall(os.remove, state.card) end
  state = nil
end

---@internal
--- Testkarte mit den aktuellen Korrekturwerten neu zeichnen.
---@return nil
local function redraw()
  if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then return end

  require("images.config").setup({
    display = { terminal_padding = { row = state.row, col = state.col } },
  })

  -- `inset = 0`: während der Kalibrierung soll die Kante des Bildes die Kante
  -- des Fensters treffen. Eine Marge würde genau das verdecken, was hier
  -- beurteilt werden soll.
  require("images.anchor").draw(state.win, "full", state.card, { defer = true, inset = 0 })
end

---@internal
--- Wie viele Zellen eine Abweichung groß ist. Die Auswahl ist bewusst grob:
--- feiner als "eine Zeile" kann niemand schätzen, und feiner als eine Zelle
--- lässt sich ohnehin nichts korrigieren.
---@type { label: string, cells: integer }[]
local MAGNITUDES = {
  { label = "weniger als eine ganze Zeile/Spalte", cells = 0 },
  { label = "etwa 1", cells = 1 },
  { label = "etwa 2", cells = 2 },
  { label = "etwa 3", cells = 3 },
  { label = "4 oder mehr", cells = 4 },
}

---@internal
---@param axis "row"|"col"
---@param direction integer -1 = Bild muss nach oben/links, +1 = nach unten/rechts
---@param unit string
---@param on_done fun()
local function ask_magnitude(axis, direction, unit, on_done)
  local items = {}
  for i, m in ipairs(MAGNITUDES) do
    items[i] = m.cells == 0 and m.label or (m.label .. " " .. unit)
  end

  choose({
    title = "Wie groß ist die Abweichung?",
    items = items,
    on_select = function(_, idx)
      local cells = MAGNITUDES[idx].cells
      if cells == 0 then
        -- Unterhalb einer Zelle: nicht korrigierbar, nur abfangbar.
        state["residual_" .. axis] = true
        on_done()
        return
      end
      state[axis] = state[axis] + direction * cells
      redraw()
      vim.defer_fn(on_done, 120)
    end,
    on_cancel = on_done,
  })
end

---@internal
--- Eine Kante beurteilen lassen und daraus den nächsten Schritt ableiten.
---@param axis "row"|"col"
---@param on_done fun()
local function ask_edge(axis, on_done)
  local vertical = axis == "row"
  local edge = vertical and "Oberkante" or "linke Kante"
  local unit = vertical and "Zeile(n)" or "Spalte(n)"

  choose({
    title = ("%s der Testkarte — was siehst du?"):format(edge),
    items = {
      "passt: Rahmen der Karte liegt genau am Fensterrand",
      vertical and "Lücke: die Karte sitzt zu weit unten" or "Lücke: die Karte sitzt zu weit rechts",
      vertical and "abgeschnitten: die Karte steht oben über" or "abgeschnitten: die Karte steht links über",
    },
    on_select = function(_, idx)
      if idx == 1 then
        on_done()
        return
      end
      -- Lücke oben  → Karte zu tief  → nach oben korrigieren  (negativ)
      -- Abgeschnitten oben → Karte zu hoch → nach unten korrigieren (positiv)
      local direction = (idx == 2) and -1 or 1
      ask_magnitude(axis, direction, unit, function()
        -- Nach jeder Korrektur dieselbe Kante erneut beurteilen: der Wert
        -- kann übers Ziel hinausgeschossen sein, und dann ist die nächste
        -- Antwort die Gegenrichtung. So konvergiert es, statt einmal zu
        -- raten.
        if state and not state["residual_" .. axis] then
          ask_edge(axis, on_done)
        else
          on_done()
        end
      end)
    end,
    on_cancel = on_done,
  })
end

---@internal
--- Ergebnis anzeigen, speichern anbieten.
---@return nil
local function finish()
  if not state then return end

  local row, col = state.row, state.col
  local residual = state.residual_row or state.residual_col
  teardown()

  local lines = {
    ("Ermittelt: terminal_padding = { row = %d, col = %d }"):format(row, col),
  }
  if residual then
    lines[#lines + 1] = "Es bleibt ein Rest unterhalb einer Zelle — der ist protokollbedingt"
    lines[#lines + 1] = "nicht korrigierbar. `display.draw_inset = 1` fängt ihn ab."
  end
  notify().info(table.concat(lines, "\n"))

  if row == 0 and col == 0 and not residual then
    notify().info("Nichts zu speichern: die Platzierung sitzt bereits.")
    return
  end

  ask_yes_no("Diese Werte dauerhaft für dieses Terminal speichern?", function(yes)
    if not yes then
      notify().info(
        ("Nicht gespeichert. Für die eigene setup()-Spec:\n" .. "display = { terminal_padding = { row = %d, col = %d } }"):format(
          row,
          col
        )
      )
      return
    end

    local ok, err = require("images.calibration").save({ terminal_padding = { row = row, col = col } })
    if ok then
      notify().info("Gespeichert. Gilt ab dem nächsten Start automatisch.")
    else
      notify().error("Speichern fehlgeschlagen: " .. tostring(err))
    end
  end)
end

--- Die Kalibrierung starten.
---@return boolean started
function M.run()
  if state then
    notify().warn("Es läuft bereits eine Kalibrierung")
    return false
  end

  local cap = require("images.terminal").capability(require("images.config").get().display.assume_supported)
  if not cap.ok then
    notify().error(cap.reason or "Terminal kann keine Bilder zeichnen")
    return false
  end

  local cols = math.max(20, math.floor(vim.o.columns * M.WINDOW.width))
  local rows = math.max(8, math.floor(vim.o.lines * M.WINDOW.height))

  local cell_aspect = require("images.scale").CELL_ASPECT
  local card, card_err = require("images.testcard").write(cols, rows, cell_aspect)
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

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.floor((vim.o.lines - rows) / 2),
    col = math.floor((vim.o.columns - cols) / 2),
    width = cols,
    height = rows,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    title = " :Image calibrate ",
  })

  local current = require("images.config").get().display.terminal_padding or {}
  state = {
    row = type(current.row) == "number" and current.row or 0,
    col = type(current.col) == "number" and current.col or 0,
    residual_row = false,
    residual_col = false,
    win = win,
    buf = buf,
    card = card,
    cols = cols,
    rows = rows,
  }

  redraw()

  -- Erst zeichnen lassen, dann fragen: die erste Frage darf nicht über einem
  -- Fenster stehen, in dem noch nichts zu sehen ist.
  vim.defer_fn(function()
    if not state then return end
    ask_edge("row", function()
      if not state then return end
      ask_edge("col", function()
        if state then finish() end
      end)
    end)
  end, 200)

  return true
end

--- Eine laufende Kalibrierung abbrechen.
---@return nil
function M.cancel()
  teardown()
end

return M
