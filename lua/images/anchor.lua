---@module 'images.anchor'
---@brief Reliably draw an image at a named position inside a window (or the
--- window showing a given buffer).
---@description
--- The one canonical home for a pattern that was previously rebuilt four times
--- independently — `images.zen`, `images.hover_float` and `images.redact` each
--- open a window and draw against its geometry, and `images.browse`'s picker
--- preview draws against the geometry of a foreign (snacks) window. Every copy
--- had its own level of care: only zen/hover_float/redact carried the
--- `vim.schedule` fix for a window opened in the same tick (see below), browse
--- did not, because its target window had been standing for a while by then.
--- From here on there is one implementation, shared by all four callers.
---
--- **Why `defer` is an explicit parameter rather than auto-detected:**
--- `nvim_ui_send` writes to the terminal immediately, but Neovim's own repaint
--- only runs once control returns to the main loop — and then covers
--- everything that turned dirty since the last return. Open a window and draw
--- into it in the same tick and the image goes out, after which Neovim paints
--- that freshly opened window's (empty) cells over it — window there, image
--- gone. `images.terminal.draw`'s own flush (`:redraw`) only catches what was
--- already pending BEFORE sending, not the repaint that opening the window
--- itself causes; for that the jump into the next tick is required
--- (`vim.schedule`). Whether a window was "just" opened cannot be detected
--- reliably from here (there is no API field for it), so the caller — who
--- knows — decides, instead of a heuristic that can be wrong in both
--- directions.

local M = {}

--- Resolve `target` to a concrete, valid window.
---   nil / 0              → current window
---   valid window handle  → unchanged
---   valid buffer handle  → a window showing that buffer (the current one
---                          first, otherwise the first one found)
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
    return nil, ("no window shows buffer %d"):format(target)
  end

  return nil, ("invalid window or buffer handle: %s"):format(tostring(target))
end

--- How many rows/columns a window's border pushes its content inwards.
---
--- `nvim_win_get_position` is unaffected by the border: for a bordered and an
--- unbordered window with identical `row`/`col` configuration it returns the
--- same value — namely the position of the border's OUTER edge, not of the
--- content. A window with a top and left border segment therefore indents its
--- actual content by one cell down/right without that showing up in `pos`
--- (verified against `screenpos()`: without a border it coincides with
--- `pos + 1`, with `rounded`/`single` it is exactly one cell more in both row
--- and column). Ignore that offset and you draw one cell too early — visible
--- as an image overlapping the border instead of sitting inside it.
--- `images.scale.anchor_box` is not affected: `nvim_win_get_width`/`_height`
--- already report the content area only, identically with or without a border.
---
--- The trailing segments are returned as well. They do not indent anything --
--- nothing is drawn against the bottom or right edge -- but `placed_position`
--- needs them to know a floating window's full extent on screen.
---@param winid integer already verified as valid
---@return integer row_inset 0 or 1 rows the top border indents the content
---@return integer col_inset 0 or 1 columns the left border indents the content
---@return integer row_trail 0 or 1 rows the bottom border occupies
---@return integer col_trail 0 or 1 columns the right border occupies
local function border_inset(winid)
  local ok, config = pcall(vim.api.nvim_win_get_config, winid)
  if not ok then return 0, 0, 0, 0 end

  local border = config.border
  if type(border) ~= "table" then return 0, 0, 0, 0 end -- "none", or no border set

  -- Order per `:h nvim_open_win()`: {top-left, top, top-right, right,
  -- bottom-right, bottom, bottom-left, left}. Each segment is either a
  -- character or a {character, highlight} pair. Top/left indent the content as
  -- soon as one of their three participating segments is filled -- a top-only
  -- border without a left segment shifts the row but not the column.
  local function present(...)
    for _, i in ipairs({ ... }) do
      local seg = border[i]
      if type(seg) == "table" then seg = seg[1] end
      if type(seg) == "string" and seg ~= "" then return true end
    end
    return false
  end

  return (present(1, 2, 3) and 1 or 0),
    (present(1, 7, 8) and 1 or 0),
    (present(5, 6, 7) and 1 or 0),
    (present(3, 4, 5) and 1 or 0)
end

---@internal
--- Where a window is actually drawn, as opposed to where it asked to be.
---
--- A floating window that would overhang the screen edge is not drawn where its
--- configuration puts it: Neovim moves it back inside. **`nvim_win_get_position`
--- keeps reporting the requested position regardless**, and so does
--- `screenpos()` — there is no API that returns the placed position. Draw
--- against the reported one and the image lands beside its own frame, by
--- exactly as far as the window would have overhung.
---
--- Measured on a 170-column screen (`images-probe`, hover over a markdown link
--- with a 50-column file tree open on the left):
---
--- | reported col | content + border | `170 − extent` | drawn at |
--- | --- | --- | --- | --- |
--- | 141 | 80 + 2 | **88** | 88 |
--- | 83 | 80 + 2 | 88 | 83 (no overhang) |
--- | 34 | 102 + 2 | 66 | 34 (no overhang) |
---
--- This is why the fault only ever showed up with a file tree on the **left**:
--- it pushes the cursor right, a cursor-relative hover float then overhangs,
--- and Neovim silently moves it. A file tree on the right leaves the cursor at
--- low columns, nothing overhangs, nothing moves. `:Image calibrate` is
--- `relative = "editor"` and centred, so it never overhangs either — which is
--- what made the fault look like a hover-only problem for a long time.
---
--- Rows are clamped against the full `vim.o.lines` rather than against the
--- editable area. If Neovim reserves the command line, this bound is one row
--- too permissive and a float at the very bottom stays as wrong as before —
--- deliberately, because the opposite error would shift correctly placed
--- images. Only the horizontal case is measured; the vertical one follows the
--- same rule because the mechanism is not axis-specific.
---@param winid integer already verified as valid
---@param pos integer[] `nvim_win_get_position` result
---@param extent_rows integer content height plus both horizontal border segments
---@param extent_cols integer content width plus both vertical border segments
---@return integer row
---@return integer col
local function placed_position(winid, pos, extent_rows, extent_cols)
  local ok, config = pcall(vim.api.nvim_win_get_config, winid)
  -- Split windows are laid out by Neovim and always fit; only floats move.
  if not ok or config.relative == nil or config.relative == "" then return pos[1], pos[2] end

  local row = math.max(0, math.min(pos[1], vim.o.lines - extent_rows))
  local col = math.max(0, math.min(pos[2], vim.o.columns - extent_cols))
  return row, col
end

--- Additional fixed row/column offset from `display.terminal_padding` —
--- default `{ row = 0, col = 0 }`, a plain no-op for anyone without it.
---
--- The reason: some terminals (WezTerm demonstrably, see
--- docs/ROADMAP/TERMINALS.md) account for their own `window_padding` correctly
--- when painting text and borders, but not when placing an OSC 1337 image —
--- the image then lands as many pixels too low/too far right as the window has
--- padding. `CSI row;col H` positions in whole cells only; padding that is not
--- an even multiple of the cell size therefore cannot be compensated at all
--- (that would need a pixel offset, which OSC 1337 does not have). Put the
--- padding on a cell multiple and the remainder — now a whole-cell row/column
--- offset — can be compensated here. `:Image calibrate` measures it
--- interactively; see `images.calibrate`.
---@param override { row: integer?, col: integer? }|nil value from `Images.Anchor.Opts.padding`
---@return integer row
---@return integer col
local function terminal_padding(override)
  local padding = override

  -- Only consult the configuration when the caller brought nothing.
  -- `images.calibrate` tries values out and must not rewrite the global
  -- configuration to do so -- a value being tried is not a setting.
  if type(padding) ~= "table" then
    local ok, config = pcall(require, "images.config")
    if not ok then return 0, 0 end
    padding = (config.get().display or {}).terminal_padding
  end
  if type(padding) ~= "table" then return 0, 0 end

  local row = type(padding.row) == "number" and math.floor(padding.row) or 0
  local col = type(padding.col) == "number" and math.floor(padding.col) or 0
  return row, col
end

--- Margin in cells kept free all round inside the window.
---
--- **Why at all.** Placing an image flush against the frame only looks good if
--- the placement is cell-accurate. That cannot be guaranteed: terminals whose
--- window padding is not a multiple of the cell size shift the image by a
--- fraction of a cell (WezTerm demonstrably, see docs/ROADMAP/TERMINALS.md),
--- and neither cell size nor padding can be queried from inside Neovim (`:h
--- TermResponse` forwards no CSI replies). Drawn flush, such an offset turns
--- into a visible overhang past the frame.
---
--- **Why all round rather than only where the offset goes.** One-sided would
--- cost half the area — and still looks worse. Measured on the test case: with
--- the reserve only at bottom/right, the image clings to the left border and
--- leaves a gap on the right, and that asymmetry reads as a defect regardless
--- of what it prevents. Spread all round, the same tolerance becomes an even
--- inner margin that looks deliberate. A *systematic* offset does not belong
--- here anyway but in `display.terminal_padding` — the margin only absorbs the
--- remainder.
---
--- Once a setup is measured (`display.cell_aspect`,
--- `display.terminal_padding`), `display.draw_inset = 0` draws flush.
---@param explicit integer|nil value from `Images.Anchor.Opts.inset`
---@return integer cells >= 0
local function draw_inset(explicit)
  if type(explicit) == "number" then return math.max(0, math.floor(explicit)) end

  local ok, config = pcall(require, "images.config")
  if not ok then return 0 end

  local configured = (config.get().display or {}).draw_inset
  return type(configured) == "number" and math.max(0, math.floor(configured)) or 0
end

---@param winid integer already verified as valid
---@param position string see `images.scale.POSITIONS`
---@param file string
---@param scale number|nil
---@param inset integer|nil
---@param padding { row: integer?, col: integer? }|nil
---@return boolean ok
---@return string|nil err
local function draw_now(winid, position, file, scale, inset, padding)
  if not vim.api.nvim_win_is_valid(winid) then return false, "window is no longer valid" end

  local pos = vim.api.nvim_win_get_position(winid)
  local width = vim.api.nvim_win_get_width(winid)
  local height = vim.api.nvim_win_get_height(winid)
  local row_inset, col_inset = border_inset(winid)
  local pad_row, pad_col = terminal_padding(padding)

  local cols, rows, col_off, row_off, box_err = require("images.scale").anchor_box(width, height, position, scale)
  if not (cols and rows and col_off and row_off) then return false, box_err end

  -- Margin all round, box stays centred. Capped per axis so that even in a
  -- very small window at least one cell of image survives -- a margin that
  -- eats the image entirely would be worse than none.
  local margin = draw_inset(inset)
  if margin > 0 then
    local mc = math.min(margin, math.floor((cols - 1) / 2))
    local mr = math.min(margin, math.floor((rows - 1) / 2))
    if mc > 0 then
      cols, col_off = cols - 2 * mc, col_off + mc
    end
    if mr > 0 then
      rows, row_off = rows - 2 * mr, row_off + mr
    end
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
---@field scale number|nil 0 < scale <= 1; ignored for `position = "full"`; otherwise defaults to `images.scale.DEFAULT_ANCHOR_SCALE`
---@field defer boolean|nil `vim.schedule` before drawing — required when `target` was opened/filled in the same tick (see module docs). Default `false`.
---@field inset integer|nil safety margin in cells all round; `nil` = `display.draw_inset` from the configuration, `0` = flush. See `draw_inset`.
---@field padding { row: integer?, col: integer? }|nil cell offset instead of `display.terminal_padding`; for callers trying values out without changing the configuration
---@field on_done fun(ok: boolean, err: string|nil)|nil runs exactly once in every case — synchronously for `defer = false` (or when `target` cannot be resolved at all), otherwise as soon as the deferred draw attempt has settled

--- Draw an image into `target` at `position`.
---@param target integer|nil window or buffer handle; nil/0 = current window
---@param position string see `images.scale.POSITIONS`
---@param file string absolute path
---@param opts Images.Anchor.Opts|nil
---@return boolean ok for `defer = true`: whether the call was accepted, not whether anything was drawn yet
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
      local ok, err = draw_now(winid, position, file, opts.scale, opts.inset, opts.padding)
      if opts.on_done then opts.on_done(ok, err) end
    end)
    return true
  end

  local ok, err = draw_now(winid, position, file, opts.scale, opts.inset, opts.padding)
  if opts.on_done then opts.on_done(ok, err) end
  return ok, err
end

return M
