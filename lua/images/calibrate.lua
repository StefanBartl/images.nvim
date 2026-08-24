---@module 'images.calibrate'
---@brief `:Image calibrate` — measure image placement instead of guessing it.
---@description
--- A terminal may place an image somewhere other than `CSI row;col H` asked
--- for: WezTerm does not account for its own `window_padding` when placing an
--- OSC 1337 image, and terminals with their own window chrome presumably
--- behave the same (measurements: docs/ROADMAP/TERMINALS.md). The offset
--- cannot be detected from inside Neovim — `:h TermResponse` forwards no CSI
--- replies and `nvim_list_uis()` reports no pixels — and it is not even
--- constant: the same value was right at one cursor position and already
--- overshooting at another. A number written into the docs would therefore be
--- wrong even for a single setup.
---
--- That leaves asking the person who can see it.
---
--- **Why nudging rather than questions.** The first version drew a test card
--- and asked, through a select popup, what each edge looked like. It could not
--- work, for exactly the reason `images.anchor` documents: the popup is a
--- window, and Neovim paints over the cells it covers — including the image
--- being judged. What remained was an empty frame and a question about it.
---
--- Nudging resolves both problems at once. There is no second window to cover
--- anything, and every keypress redraws anyway, so the repaint that used to be
--- the problem is now part of the loop. Above all, nobody has to estimate:
--- instead of "how many lines is it out by", it is "push until it sits" — the
--- same information, without the detour through a number that cannot be read
--- off a screen.
---
--- **What stays unsolvable.** `CSI row;col H` addresses whole cells, so
--- nudging moves in whole cells too. If the real offset is a fraction of one,
--- the card steps over the correct position without ever landing on it. The
--- window says so while it is open, and `display.draw_inset` is what covers
--- the remainder — that is the protocol's limit, and it belongs stated rather
--- than hidden.

local M = {}

--- Calibration window size in cells, as a fraction of the editor. Large
--- enough that a single cell of offset is obvious, small enough that text
--- remains visible around it — that surrounding text is what makes the window
--- border readable as an edge in the first place.
M.WINDOW = { width = 0.6, height = 0.6 }

---@class Images.Calibrate.State
---@field row integer current row correction
---@field col integer current column correction
---@field win integer|nil
---@field buf integer|nil
---@field card string|nil path of the generated test card
---@field prev_win integer|nil window focused before calibration started

---@type Images.Calibrate.State|nil
local state = nil

---@internal
--- Same pattern as `images.redact` and the other modules: `lib.nvim.notify`
--- is a factory, not a ready-made notifier.
---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@internal
--- Window title and footer. The title carries the live values so nobody has
--- to count keypresses; the footer carries the keys *and* the whole-cell
--- caveat, because a caveat that only appears in a dismissable notification
--- is a caveat nobody reads.
---
--- The caveat is dropped rather than truncated on a narrow window: half a
--- sentence about a limitation is worse than none, because it reads like a
--- rendering glitch instead of a statement.
---@return string title
---@return string footer
local function labels()
  local row = state and state.row or 0
  local col = state and state.col or 0
  local title = (" Calibration   row %d   col %d "):format(row, col)

  local keys = " hjkl/arrows move · r reset · <CR> accept · q cancel "
  local caveat = "· whole cells only, any smaller offset needs display.draw_inset "

  local width = 0
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then width = vim.api.nvim_win_get_width(state.win) end
  if vim.fn.strdisplaywidth(keys .. caveat) <= width then return title, keys .. caveat end
  return title, keys
end

---@internal
--- Redraw the test card with the current corrections.
---
--- `padding` travels as a call option rather than through `images.config`: a
--- value someone is still trying out is not a setting, and a calibration that
--- rewrites the running configuration on the way would be worse than the
--- problem it solves.
---
--- `inset = 0` because the card's edge has to meet the window's edge here — a
--- margin would hide the very thing being judged.
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
--- Close the window, delete the test card, hand focus back.
---@return nil
local function teardown()
  if not state then return end
  local prev, card, win = state.prev_win, state.card, state.win
  state = nil

  pcall(function()
    require("images.terminal").clear()
  end)
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  if prev and vim.api.nvim_win_is_valid(prev) then pcall(vim.api.nvim_set_current_win, prev) end
  if card then pcall(os.remove, card) end
end

---@internal
--- Report the result and offer to persist it.
---@param row integer
---@param col integer
---@return nil
local function offer_save(row, col)
  if row == 0 and col == 0 then
    notify().info("Nothing to save — placement already sits without a correction.")
    return
  end

  local summary = ("terminal_padding = { row = %d, col = %d }"):format(row, col)

  local function persist()
    local config = require("images.config")
    local ok, err = require("images.calibration").save({ terminal_padding = { row = row, col = col } })
    if not ok then
      notify().error("Could not save: " .. tostring(err))
      return
    end

    -- A hand-written option outranks the stored calibration by design. Saying
    -- so is the point: a measurement that silently does nothing is worse than
    -- no measurement, because it looks like it worked.
    local shadowed = (config.user_opts().display or {}).terminal_padding ~= nil
    if shadowed then
      notify().warn(
        "Saved, but display.terminal_padding in your setup() spec takes precedence\n"
          .. "and will keep overriding it. Remove it there to use the measured value,\n"
          .. "or replace it with: "
          .. summary
      )
      return
    end

    notify().info("Saved (" .. summary .. ").\nActive now and after every restart.")
    config.setup(config.user_opts())
  end

  local function decline()
    notify().info("Not saved. For your own setup() spec:\ndisplay = { " .. summary .. " }")
  end

  local ok_confirm, confirm = pcall(require, "lib.nvim.ui.kit.confirm")
  if ok_confirm and type(confirm.open) == "function" then
    confirm.open({
      question = "Apply this calibration?\n" .. summary,
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

  vim.ui.select({ "Save", "Just show me the values" }, { prompt = "Apply this calibration? " .. summary }, function(_, idx)
    if idx == 1 then
      persist()
    else
      decline()
    end
  end)
end

---@internal
--- Keys for the calibration window. Deliberately both: arrows for the first
--- attempt, `hjkl` for fingers that already know where to reach.
---@param buf integer
---@return nil
local function set_keymaps(buf)
  local function nudge(d_row, d_col)
    return function()
      if not state then return end
      state.row = state.row + d_row
      state.col = state.col + d_col
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        local title, footer = labels()
        pcall(vim.api.nvim_win_set_config, state.win, { title = title, footer = footer })
      end
      redraw()
    end
  end

  local map = vim.keymap.set
  local o = { buffer = buf, nowait = true, silent = true }

  ---@param keys string[]
  ---@param fn function
  ---@param desc string
  local function bind(keys, fn, desc)
    for _, key in ipairs(keys) do
      map("n", key, fn, vim.tbl_extend("force", o, { desc = "images.calibrate: " .. desc }))
    end
  end

  bind({ "k", "<Up>" }, nudge(-1, 0), "move image up")
  bind({ "j", "<Down>" }, nudge(1, 0), "move image down")
  bind({ "h", "<Left>" }, nudge(0, -1), "move image left")
  bind({ "l", "<Right>" }, nudge(0, 1), "move image right")

  bind({ "r" }, function()
    if not state then return end
    state.row, state.col = 0, 0
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local title, footer = labels()
      pcall(vim.api.nvim_win_set_config, state.win, { title = title, footer = footer })
    end
    redraw()
  end, "reset")

  bind({ "<CR>" }, function()
    if not state then return end
    local row, col = state.row, state.col
    teardown()
    -- Only ask once the window is gone: while the image is still on screen the
    -- dialog would paint over it (see the module docs).
    vim.schedule(function()
      offer_save(row, col)
    end)
  end, "accept")

  bind({ "q", "<Esc>" }, function()
    teardown()
    notify().info("Calibration cancelled")
  end, "cancel")
end

--- Start calibration.
---@return boolean started
function M.run()
  if state then
    notify().warn("A calibration is already running")
    return false
  end

  local display = require("images.config").get().display
  local cap = require("images.terminal").capability(display.assume_supported)
  if not cap.ok then
    notify().error(cap.reason or "This terminal cannot draw images")
    return false
  end

  local cols = math.max(20, math.floor(vim.o.columns * M.WINDOW.width))
  local rows = math.max(8, math.floor(vim.o.lines * M.WINDOW.height))

  local card, card_err = require("images.testcard").write(cols, rows, require("images.scale").CELL_ASPECT)
  if not card then
    notify().error(card_err or "Could not build the test card")
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

  local configured = display.terminal_padding or {}
  local prev_win = vim.api.nvim_get_current_win()

  state = {
    row = type(configured.row) == "number" and configured.row or 0,
    col = type(configured.col) == "number" and configured.col or 0,
    win = nil,
    buf = buf,
    card = card,
    prev_win = prev_win,
  }

  local title, footer = labels()
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - rows) / 2),
    col = math.floor((vim.o.columns - cols) / 2),
    width = cols,
    height = rows,
    style = "minimal",
    border = "rounded",
    noautocmd = true,
    title = title,
    footer = footer,
    footer_pos = "center",
  })

  set_keymaps(buf)
  redraw()

  return true
end

--- Abort a running calibration.
---@return nil
function M.cancel()
  teardown()
end

return M
