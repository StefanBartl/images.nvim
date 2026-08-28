---@module 'images.debug'
---@brief `:Image debug` — measure where an image actually lands, and why.
---@description
--- Placement bugs in this plugin have a recurring shape: every number checks
--- out and the picture is still in the wrong place. The arithmetic is
--- verifiable from inside Neovim; where the terminal *puts* the result is not.
--- Closing that gap needs a measurement, and the measurements that found the
--- two real bugs (see docs/ROADMAP/TERMINALS.md, failure modes 6 and 7) were
--- one-off scripts in a personal config — useless to anyone else hitting the
--- same thing.
---
--- So they live here. Three modes, each answering one question:
---
---   `report`   what coordinates go to the terminal, per draw, against an
---              independently recomputed expectation. Arms an observer;
---              `:Image debug report` again prints what it collected.
---   `columns`  draws the same card at four columns. A displacement that
---              grows left-to-right is a scale error (nothing here can fix
---              it); a constant one is an offset (`terminal_padding` can).
---   `float`    opens a float and draws into it, with a marker at the
---              float's *reported* corner. Marker off the corner means the
---              window is not where Neovim says it is — which is exactly
---              failure mode 7.
---
--- **Why a generated card is not enough.** `images.testcard` builds its card
--- to whatever box it is given, so it fills any frame by construction and can
--- never reveal an aspect-ratio problem. `columns`/`float` therefore accept a
--- real image path, and using one is the point rather than a convenience:
--- the letterboxing bug was invisible to every card-based test.

local M = {}

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@type table[]
local log = {}

---@type boolean
local armed = false

---@internal
--- Border inset of a window: 1 when any segment is set, else 0. A local copy
--- rather than reaching into `images.anchor`'s private helper -- a diagnostic
--- that shares code with the thing it measures cannot contradict it.
---@param win integer
---@return integer
local function border_of(win)
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if not ok or type(cfg.border) ~= "table" then return 0 end
  for _, seg in ipairs(cfg.border) do
    local ch = type(seg) == "table" and seg[1] or seg
    if type(ch) == "string" and ch ~= "" then return 1 end
  end
  return 0
end

---@internal
--- The newest floating window, which for a hover or preview is the one just
--- opened. Good enough for a diagnostic, and it avoids requiring callers to
--- hand a window in.
---@return integer|nil
local function newest_float()
  local best = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, w)
    if ok and cfg.relative and cfg.relative ~= "" then
      if not best or w > best then best = w end
    end
  end
  return best
end

---@internal
--- Wrap `images.terminal.draw` so every draw is recorded. Idempotent: the
--- untouched function is kept on the module, so arming twice wraps the
--- original rather than the previous wrapper.
---@return nil
local function arm()
  if armed then return end
  local term = require("images.terminal")
  term.__debug_draw = term.__debug_draw or term.draw

  term.draw = function(file, row, col, cols, rows)
    local entry = {
      file = vim.fn.fnamemodify(tostring(file), ":t"),
      screen_cols = vim.o.columns,
      screen_rows = vim.o.lines,
      sent_row = row,
      sent_col = col,
      sent_w = cols,
      sent_h = rows,
    }

    local cur = vim.api.nvim_get_current_win()
    local ok_pos, wpos = pcall(vim.api.nvim_win_get_position, cur)
    if ok_pos then entry.win_col = wpos[2] end

    local f = newest_float()
    if f then
      local fpos = vim.api.nvim_win_get_position(f)
      local b = border_of(f)
      entry.f_row, entry.f_col = fpos[1], fpos[2]
      entry.f_w = vim.api.nvim_win_get_width(f)
      entry.f_h = vim.api.nvim_win_get_height(f)
      entry.fits = (fpos[2] + entry.f_w + 2 * b) <= vim.o.columns

      local display = require("images.config").get().display or {}
      local inset = type(display.draw_inset) == "number" and display.draw_inset or 0
      local pad = display.terminal_padding or {}
      entry.exp_row = fpos[1] + b + 1 + inset + (pad.row or 0)
      entry.exp_col = fpos[2] + b + 1 + inset + (pad.col or 0)
      entry.d_row = row - entry.exp_row
      entry.d_col = col - entry.exp_col
    end

    log[#log + 1] = entry
    return term.__debug_draw(file, row, col, cols, rows)
  end

  armed = true
end

---@internal
--- Draw a small card at `row`/`col`, 1-based terminal cells. Used to mark a
--- window's reported corner: it goes through the same `terminal.draw` the
--- images use, which is proven to place correctly at any screen column, so
--- where the marker lands is where that coordinate really is.
---@param row integer
---@param col integer
---@return nil
local function mark(row, col)
  local ok, testcard = pcall(require, "images.testcard")
  if not ok then return end
  local card = testcard.write(4, 2, require("images.scale").CELL_ASPECT)
  if not card then return end
  local term = require("images.terminal");
  (term.__debug_draw or term.draw)(card, row, col, 4, 2)
  vim.defer_fn(function()
    pcall(os.remove, card)
  end, 5000)
end

--- Arm the observer, or print what it has collected.
---@return nil
function M.report()
  if not armed then
    arm()
    log = {}
    notify().info("Recording draws. Hover or show images, then run `:Image debug report` again.")
    return
  end

  if #log == 0 then
    notify().warn("Nothing recorded yet — show an image first.")
    return
  end

  local out = {
    ("screen %dx%d"):format(log[1].screen_cols or 0, log[1].screen_rows or 0),
    "",
    "file                  win  float@     size    sent@     expect@   delta",
    "--------------------  ---  ---------  ------  --------  --------  ------",
  }
  for _, e in ipairs(log) do
    if e.f_col then
      out[#out + 1] = ("%-20s  %-3s  r%-2d c%-4d  %2dx%-2d  r%-2d c%-4d  r%-2d c%-4d  %+d/%+d%s"):format(
        e.file:sub(1, 20),
        tostring(e.win_col or "?"),
        e.f_row,
        e.f_col,
        e.f_w,
        e.f_h,
        e.sent_row,
        e.sent_col,
        e.exp_row,
        e.exp_col,
        e.d_row,
        e.d_col,
        e.fits and "" or "  OVERHANG"
      )
    else
      out[#out + 1] = ("%-20s  (no float — drawn over text)"):format(e.file:sub(1, 20))
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "win     = editor window origin column (a file tree's width; 0 = none)"
  out[#out + 1] = "delta   = sent minus independently recomputed. 0/0 means consistent"
  out[#out + 1] = "          with the REPORTED float position — not that the position is"
  out[#out + 1] = "          right. Use `:Image debug float` for that."

  notify().info(table.concat(out, "\n"))
end

--- Draw the same card at four columns: is a displacement constant or growing?
---@param path string|nil real image instead of a generated card
---@return nil
function M.columns(path)
  local ok_card, testcard = pcall(require, "images.testcard")
  if not ok_card then
    notify().error("images.testcard unavailable")
    return
  end

  local COLS, ROWS = 12, 6
  local card = path and vim.fn.expand(path) or testcard.write(COLS, ROWS, require("images.scale").CELL_ASPECT)
  if not card or (path and vim.fn.filereadable(card) == 0) then
    notify().error("could not read: " .. tostring(card))
    return
  end

  local targets = {}
  for _, frac in ipairs({ 0.05, 0.3, 0.55, 0.8 }) do
    local c = math.floor(vim.o.columns * frac)
    targets[#targets + 1] = math.max(1, math.min(c, vim.o.columns - COLS - 2))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local lines = {}
  for i = 1, vim.o.lines do
    lines[i] = string.rep(" ", vim.o.columns)
  end
  for i, col in ipairs(targets) do
    local row = 2 + (i - 1) * (ROWS + 2)
    local label = ("|<- col %d"):format(col)
    local head = lines[row]:sub(1, col - 1)
    lines[row] = head .. label .. lines[row]:sub(col + #label)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_get_current_win()
  -- `wrap` off is not cosmetic: a full-width marker line otherwise wraps and
  -- the column a marker sits in stops meaning anything.
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"

  vim.keymap.set("n", "q", function()
    pcall(require("images.terminal").clear)
    if not path then pcall(os.remove, card) end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end, { buffer = buf, nowait = true, desc = "images.debug: clear" })

  -- A tick later: Neovim repaints what turned dirty since the last return to
  -- its main loop, so drawing in this tick puts the cards out and then paints
  -- the buffer over them.
  vim.schedule(function()
    for i, col in ipairs(targets) do
      local row = 2 + (i - 1) * (ROWS + 2)
      require("images.terminal").draw(card, row + 1, col, COLS, ROWS)
    end
    vim.defer_fn(function()
      notify().info(
        "Each card's LEFT EDGE belongs under the '|' above it.\n"
          .. "Same error on all four  -> constant offset; display.terminal_padding can fix it.\n"
          .. "Growing top to bottom   -> a scale error; terminal_padding cannot.\n"
          .. "Press q to clear."
      )
    end, 400)
  end)
end

--- Open a float and draw into it, marking the float's reported corner.
---@param cols integer|nil
---@param rows integer|nil
---@param path string|nil real image instead of a generated card
---@return nil
function M.float(cols, rows, path)
  cols = cols or 71
  rows = rows or 20

  local ok_anchor, anchor = pcall(require, "images.anchor")
  local ok_card, testcard = pcall(require, "images.testcard")
  if not (ok_anchor and ok_card) then
    notify().error("images.anchor/testcard unavailable")
    return
  end

  local card = path and vim.fn.expand(path) or testcard.write(cols, rows, require("images.scale").CELL_ASPECT)
  if not card or (path and vim.fn.filereadable(card) == 0) then
    notify().error("could not read: " .. tostring(card))
    return
  end

  local host = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.max(1, vim.api.nvim_win_get_position(host)[1] + 2),
    col = math.max(0, vim.api.nvim_win_get_position(host)[2] + 2),
    width = cols,
    height = rows,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })
  local fpos = vim.api.nvim_win_get_position(win)

  -- `inset = 0` so the card meets the frame's inner corner exactly. With a
  -- real image the aspect ratio may still leave slack -- that is the other
  -- failure mode, and telling the two apart is the point of running both.
  anchor.draw(win, "full", card, { defer = true, inset = 0, padding = { row = 0, col = 0 } })

  vim.schedule(function()
    mark(fpos[1] + 1, fpos[2] + 1)
  end)

  vim.keymap.set("n", "q", function()
    pcall(require("images.terminal").clear)
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    if not path then pcall(os.remove, card) end
  end, { buffer = vim.api.nvim_win_get_buf(host), nowait = true, desc = "images.debug: clear" })

  vim.defer_fn(function()
    notify().info(
      ("float %dx%d reported at row=%d col=%d\n"):format(cols, rows, fpos[1], fpos[2])
        .. "A marker is drawn at that reported corner.\n"
        .. "  marker ON the frame's corner   -> the window is where it says it is\n"
        .. "  marker AWAY from the corner    -> it is not, and that distance is the bug\n"
        .. (path and "" or "Re-run with a real image path: a generated card is built to the\nbox and cannot reveal an aspect-ratio problem.\n")
        .. "Press q to clear."
    )
  end, 600)
end

return M
