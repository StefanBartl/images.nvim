---@module 'images.anchor'
---@brief Ein Bild zuverlässig in einem Fenster (oder dem Fenster, das einen
--- Buffer zeigt) an einer benannten Position zeichnen.
---@description
--- Die eine kanonische Stelle für ein Muster, das vorher viermal unabhängig
--- voneinander nachgebaut wurde — `images.zen`, `images.hover_float` und
--- `images.redact` öffnen je ein Fenster und zeichnen an dessen Geometrie,
--- `images.browse`s Picker-Vorschau zeichnet an der Geometrie eines
--- fremden (snacks-)Fensters. Jede Kopie hatte ihre eigene Sorgfaltsstufe:
--- nur zen/hover_float/redact hatten den `vim.schedule`-Fix für ein im
--- selben Tick geöffnetes Fenster (siehe unten), browse nicht, weil sein
--- Zielfenster beim Aufruf schon länger stand. Ab hier gibt es nur noch
--- eine Implementierung, die alle vier Aufrufer teilen.
---
--- **Warum `defer` ein expliziter Parameter ist, keine automatische
--- Erkennung:** `nvim_ui_send` schreibt sofort ans Terminal, Neovims eigener
--- Repaint läuft aber erst, wenn die Steuerung in die Hauptschleife
--- zurückkehrt — und zwar über alles, was seit dem letzten Rücksprung
--- schmutzig wurde. Wer ein Fenster öffnet und im selben Tick hineinzeichnet,
--- sendet das Bild, und Neovim malt die (leeren) Zellen dieses gerade erst
--- geöffneten Fensters danach darüber — Fenster da, Bild weg. `images.
--- terminal.draw`s eigener Flush (`:redraw`) fängt nur ab, was VOR dem
--- Senden bereits anstand, nicht den Repaint, den das Öffnen selbst nach
--- sich zieht — dafür muss der Sprung in den nächsten Tick sein
--- (`vim.schedule`). Ob ein Fenster "gerade erst" geöffnet wurde, lässt sich
--- von hier aus nicht zuverlässig erkennen (kein API-Feld dafür); deshalb
--- entscheidet der Aufrufer, der es weiß, statt einer Heuristik, die in
--- beide Richtungen falsch liegen kann.

local M = {}

--- `target` zu einem konkreten, validen Fenster auflösen.
---   nil / 0                → aktuelles Fenster
---   valides Fenster-Handle → unverändert
---   valides Buffer-Handle  → ein Fenster, das diesen Buffer zeigt (das
---                            aktuelle zuerst, sonst das erste gefundene)
---@param target integer|nil
---@return integer|nil winid
---@return string|nil err
function M.resolve_window(target)
  if target == nil or target == 0 then return vim.api.nvim_get_current_win() end

  if vim.api.nvim_win_is_valid(target) then return target end

  if vim.api.nvim_buf_is_valid(target) then
    local current = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(current) == target then return current end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == target then return w end
    end
    return nil, ("Kein Fenster zeigt Buffer %d"):format(target)
  end

  return nil, ("Ungültiges Fenster- oder Buffer-Handle: %s"):format(tostring(target))
end

--- Wie viele Zeilen/Spalten der Rahmen eines Fensters dessen Inhalt nach
--- innen schiebt.
---
--- `nvim_win_get_position` bleibt vom Rahmen unberührt: es liefert für ein
--- gerahmtes wie für ein rahmenloses Fenster mit identischer `row`/`col`-
--- Konfiguration denselben Wert — nämlich die Position der Rahmen-
--- AUSSENKANTE, nicht die des Inhalts. Ein Fenster mit oberem und linkem
--- Rahmensegment rückt seinen tatsächlichen Inhalt deshalb um je eine Zelle
--- nach unten/rechts ein, ohne dass sich das in `pos` niederschlägt (per
--- `screenpos()` gegengeprüft: ohne Rahmen deckungsgleich mit `pos + 1`, mit
--- `rounded`/`single` genau eine Zelle mehr in Zeile und Spalte). Wer diesen
--- Versatz ignoriert, zeichnet eine Zelle zu früh — sichtbar als Bild, das
--- den Rahmen überlappt statt in ihm zu sitzen. `images.scale.anchor_box`
--- ist davon nicht betroffen: `nvim_win_get_width`/`_height` geben bereits
--- nur den Inhaltsbereich zurück, mit oder ohne Rahmen identisch.
---@param winid integer bereits als gültig geprüft
---@return integer row_inset 0 oder 1
---@return integer col_inset 0 oder 1
local function border_inset(winid)
  local ok, config = pcall(vim.api.nvim_win_get_config, winid)
  if not ok then return 0, 0 end

  local border = config.border
  if type(border) ~= "table" then return 0, 0 end -- "none" oder kein Rahmen gesetzt

  -- Reihenfolge laut `:h nvim_open_win()`: {top-left, top, top-right, right,
  -- bottom-right, bottom, bottom-left, left}. Jedes Segment ist entweder ein
  -- Zeichen oder ein {Zeichen, Highlight}-Paar. Oben/links schieben den
  -- Inhalt ein, sobald eines ihrer drei beteiligten Segmente belegt ist —
  -- ein reiner Top-Rahmen ohne linkes Segment verschiebt z.B. nur die Zeile.
  local function present(...)
    for _, i in ipairs({ ... }) do
      local seg = border[i]
      if type(seg) == "table" then seg = seg[1] end
      if type(seg) == "string" and seg ~= "" then return true end
    end
    return false
  end

  return (present(1, 2, 3) and 1 or 0), (present(1, 7, 8) and 1 or 0)
end

--- Zusätzlicher, fest konfigurierter Zeilen-/Spalten-Versatz aus
--- `display.terminal_padding` — Default `{ row = 0, col = 0 }`, für alle
--- ohne diese Einstellung ein reines No-op.
---
--- Grund: manche Terminals (WezTerm nachweislich, siehe docs/ROADMAP/
--- TERMINALS.md) berücksichtigen ihr eigenes `window_padding` beim Malen von
--- Text/Rahmen korrekt, aber nicht beim Platzieren eines OSC-1337-Bildes —
--- das Bild landet dann so viele Pixel zu tief/weit rechts, wie das Fenster
--- Padding hat. `CSI row;col H` positioniert nur in ganzen Zellen; ein
--- Padding, das kein glattes Vielfaches der Zellgröße ist, lässt sich damit
--- grundsätzlich nicht ausgleichen (dafür bräuchte es einen Pixel-Offset,
--- den OSC 1337 nicht kennt). Wer sein Padding auf ein Zell-Vielfaches legt,
--- kann den Rest — jetzt ein ganzzahliger Zeilen-/Spaltenversatz — hierüber
--- kompensieren. Messprotokoll: `docs/ROADMAP/TERMINALS.md`.
---@return integer row
---@return integer col
local function terminal_padding()
  local ok, config = pcall(require, "images.config")
  if not ok then return 0, 0 end

  local padding = (config.get().display or {}).terminal_padding
  if type(padding) ~= "table" then return 0, 0 end

  local row = type(padding.row) == "number" and math.floor(padding.row) or 0
  local col = type(padding.col) == "number" and math.floor(padding.col) or 0
  return row, col
end

--- Sicherheitsreserve in Zellen, die am **unteren und rechten** Rand des
--- Fensters frei bleibt.
---
--- **Warum überhaupt.** Ein Bild exakt in den Rahmen zu legen sieht nur dann
--- gut aus, wenn die Platzierung zellgenau stimmt. Das lässt sich nicht
--- garantieren: Terminals mit einem Fenster-Padding, das kein Vielfaches der
--- Zellgröße ist, verschieben das Bild um Bruchteile einer Zelle (WezTerm
--- nachweislich, siehe docs/ROADMAP/TERMINALS.md), und weder Zellgröße noch
--- Padding sind aus Neovim heraus abfragbar (`:h TermResponse` reicht keine
--- CSI-Antworten durch). Bündig gezeichnet wird aus so einem Versatz ein
--- sichtbarer Überstand über den Rahmen.
---
--- **Warum nur unten und rechts, nicht rundum.** Der Versatz hat immer
--- dasselbe Vorzeichen: Fenster-Padding schiebt Inhalt vom Ursprung *weg*,
--- also nach unten und rechts, nie dorthin zurück. Eine Reserve oben/links
--- schützt damit vor einem Fall, der nicht eintritt, und kostet trotzdem die
--- volle Zellhöhe — bei einer Zelle von rund 22 px ist das der sichtbar
--- breite Streifen über dem Bild, den eine rundum verteilte Marge erzeugt.
--- Einseitig ist die Reserve halb so teuer und schützt genau so gut: oben
--- bleibt nur der tatsächliche Versatz als schmaler Spalt, unten liegt der
--- ungenutzte Rest unsichtbar im Rahmen.
---
--- Wer sein Setup vermessen hat (`display.cell_aspect`,
--- `display.terminal_padding`), setzt `display.draw_inset = 0` und zeichnet
--- bündig.
---@param explicit integer|nil Wert aus `Images.Anchor.Opts.inset`
---@return integer cells >= 0
local function draw_inset(explicit)
  if type(explicit) == "number" then return math.max(0, math.floor(explicit)) end

  local ok, config = pcall(require, "images.config")
  if not ok then return 0 end

  local configured = (config.get().display or {}).draw_inset
  return type(configured) == "number" and math.max(0, math.floor(configured)) or 0
end

---@param winid integer bereits als gültig geprüft
---@param position string siehe `images.scale.POSITIONS`
---@param file string
---@param scale number|nil
---@param inset integer|nil
---@return boolean ok
---@return string|nil err
local function draw_now(winid, position, file, scale, inset)
  if not vim.api.nvim_win_is_valid(winid) then return false, "Fenster nicht mehr gültig" end

  local pos = vim.api.nvim_win_get_position(winid)
  local width = vim.api.nvim_win_get_width(winid)
  local height = vim.api.nvim_win_get_height(winid)
  local row_inset, col_inset = border_inset(winid)
  local pad_row, pad_col = terminal_padding()

  local cols, rows, col_off, row_off, box_err = require("images.scale").anchor_box(width, height, position, scale)
  if not (cols and rows and col_off and row_off) then return false, box_err end

  -- Reserve am unteren/rechten Rand: die Box schrumpft, ihr Ursprung bleibt.
  -- Pro Achse gedeckelt, damit selbst in einem sehr kleinen Fenster
  -- mindestens eine Zelle Bild übrig bleibt — eine Reserve, die das Bild ganz
  -- auffrisst, wäre schlechter als gar keine.
  local margin = draw_inset(inset)
  if margin > 0 then
    cols = math.max(1, cols - margin)
    rows = math.max(1, rows - margin)
  end

  require("images.terminal").clear()
  return require("images.terminal").draw(
    file,
    pos[1] + 1 + row_inset + row_off + pad_row,
    pos[2] + 1 + col_inset + col_off + pad_col,
    cols,
    rows
  )
end

---@class Images.Anchor.Opts
---@field scale number|nil 0 < scale <= 1; ignoriert bei `position = "full"`; sonst Default `images.scale.DEFAULT_ANCHOR_SCALE`
---@field defer boolean|nil `vim.schedule` vor dem Zeichnen — nötig, wenn `target` im selben Tick geöffnet/befüllt wurde (siehe Modul-Doku). Default `false`.
---@field inset integer|nil Sicherheitsmarge in Zellen rundum; `nil` = `display.draw_inset` aus der Konfiguration, `0` = bündig. Siehe `draw_inset`.
---@field on_done fun(ok: boolean, err: string|nil)|nil läuft in jedem Fall genau einmal — synchron bei `defer = false` (oder wenn `target` sich gar nicht auflösen lässt), sonst sobald der aufgeschobene Zeichenversuch feststeht

--- Ein Bild in `target` an `position` zeichnen.
---@param target integer|nil Fenster- oder Buffer-Handle; nil/0 = aktuelles Fenster
---@param position string siehe `images.scale.POSITIONS`
---@param file string absoluter Pfad
---@param opts Images.Anchor.Opts|nil
---@return boolean ok bei `defer = true`: ob der Aufruf angenommen wurde, nicht ob bereits gezeichnet ist
---@return string|nil err
function M.draw(target, position, file, opts)
  opts = opts or {}

  local winid, werr = M.resolve_window(target)
  if not winid then
    if opts.on_done then opts.on_done(false, werr) end
    return false, werr
  end

  if opts.defer then
    vim.schedule(function()
      local ok, err = draw_now(winid, position, file, opts.scale, opts.inset)
      if opts.on_done then opts.on_done(ok, err) end
    end)
    return true
  end

  local ok, err = draw_now(winid, position, file, opts.scale, opts.inset)
  if opts.on_done then opts.on_done(ok, err) end
  return ok, err
end

return M
