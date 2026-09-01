---@module 'images.calibrate'
---@brief `:Image calibrate` — measure image placement instead of guessing it.
---@description
--- A terminal may place an image somewhere other than `CSI row;col H` asked
--- for: WezTerm does not account for its own `window_padding` when placing an
--- OSC 1337 image, and terminals with their own window chrome presumably
--- behave the same (measured). The offset
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
---
--- **Why `cell_aspect` rides along in the same window.** `images.testcard`
--- builds its card to exactly the aspect ratio the *currently effective*
--- `display.cell_aspect` implies for this box — so a wrong aspect does not
--- show up as an obviously mislabelled number, it shows up as a letterbox
--- strip along one edge of an otherwise correctly positioned card, and
--- `hjkl` cannot nudge that away: it is not an offset, it is a wrong shape.
--- Before this, that strip had no explanation in the tool itself — someone
--- could calibrate padding perfectly and the image would still spill past
--- its frame on a machine whose font metrics differ from wherever
--- `cell_aspect` was last measured (the value
--- is inherently per-font, per-terminal, exactly like `terminal_padding`, and
--- just as wrong carried verbatim to a different machine). `+`/`-` nudge it
--- in 0.01 steps and rebuild the card on every press, so the same "does it
--- sit flush" judgement that already works for position also settles shape.

local M = {}

--- Calibration window size in cells, as a fraction of the editor. Large
--- enough that a single cell of offset is obvious, small enough that text
--- remains visible around it — that surrounding text is what makes the window
--- border readable as an edge in the first place.
M.WINDOW = { width = 0.6, height = 0.6 }

---@class Images.Calibrate.State
---@field row integer current row correction
---@field col integer current column correction
---@field aspect number current cell_aspect guess, always > 0
---@field cols integer content width of the calibration window, in cells
---@field rows integer content height of the calibration window, in cells
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
  local aspect = state and state.aspect or require("images.cell").default()
  local title = (" Calibration   row %d   col %d   aspect %.2f "):format(row, col, aspect)

  local keys = " hjkl/arrows move · +/- aspect · r reset · <CR> accept · q cancel "
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
--- Rebuild the test card for the current `state.aspect` and redraw it.
---
--- The card's own aspect ratio is baked in at build time (`images.testcard`),
--- so trying a different `cell_aspect` means a genuinely new file, not a
--- redraw against the old one — unlike the row/col nudge, which only changes
--- where the same card is placed. The old file is removed only after the new
--- one exists, so a failed rebuild leaves the previous card in place rather
--- than the window going blank.
---@return nil
local function regen_card()
  if not state then return end
  local card, err = require("images.testcard").write(state.cols, state.rows, state.aspect)
  if not card then
    notify().error(err or "Could not rebuild the test card")
    return
  end
  local old = state.card
  state.card = card
  if old then pcall(os.remove, old) end
  redraw()
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
---
--- "Nothing to save" means *unchanged from what is stored*, never "the value is
--- zero". Those are different questions, and conflating them made a correction
--- back to zero impossible to record: a stale `row = 1` in the state file kept
--- shifting every image down by a cell, while calibration cheerfully reported
--- that placement already sat correctly. Zero is a measurement like any other.
---@param row integer
---@param col integer
---@param aspect number
---@return nil
local function offer_save(row, col, aspect)
  local stored = require("images.calibration").load()
  local stored_padding = stored.terminal_padding or {}
  local stored_row = type(stored_padding.row) == "number" and stored_padding.row or 0
  local stored_col = type(stored_padding.col) == "number" and stored_padding.col or 0
  -- Unmeasured is the built-in assumption, not "any value at all" — comparing
  -- against a stored `nil` would otherwise always read as "changed".
  local stored_aspect = type(stored.cell_aspect) == "number" and stored.cell_aspect or require("images.cell").default()

  local padding_changed = row ~= stored_row or col ~= stored_col
  -- A tolerance rather than exact equality: `aspect` travels through 0.01
  -- nudge steps and a JSON round trip, either of which can leave the same
  -- logical value a float epsilon away from what was read back.
  local aspect_changed = math.abs(aspect - stored_aspect) > 0.001

  if not padding_changed and not aspect_changed then
    notify().info("Nothing to save — placement and aspect already match what is stored.")
    return
  end

  ---@type table
  local values = {}
  ---@type string[]
  local summary_lines = {}
  if padding_changed then
    values.terminal_padding = { row = row, col = col }
    summary_lines[#summary_lines + 1] = ("terminal_padding = { row = %d, col = %d }"):format(row, col)
  end
  if aspect_changed then
    values.cell_aspect = aspect
    summary_lines[#summary_lines + 1] = ("cell_aspect = %.2f"):format(aspect)
  end
  local summary = table.concat(summary_lines, "\n")

  local function persist()
    local config = require("images.config")
    local ok, err = require("images.calibration").save(values)
    if not ok then
      notify().error("Could not save: " .. tostring(err))
      return
    end

    -- A hand-written option outranks the stored calibration by design. Saying
    -- so is the point: a measurement that silently does nothing is worse than
    -- no measurement, because it looks like it worked. Checked per key: the
    -- two are independent options, and only one of them being shadowed should
    -- not swallow the warning for the other.
    local opts = config.user_opts().display or {}
    ---@type string[]
    local shadowed = {}
    if values.terminal_padding and opts.terminal_padding ~= nil then shadowed[#shadowed + 1] = "display.terminal_padding" end
    if values.cell_aspect and opts.cell_aspect ~= nil then shadowed[#shadowed + 1] = "display.cell_aspect" end

    if #shadowed > 0 then
      notify().warn(
        "Saved, but "
          .. table.concat(shadowed, " and ")
          .. " in your setup() spec takes\n"
          .. "precedence and will keep overriding it. Remove it there to use the measured\n"
          .. "value, or replace it with:\n"
          .. summary
      )
      return
    end

    notify().info("Saved (" .. summary .. ").\nActive now and after every restart.")
    config.setup(config.user_opts())
    -- `terminal_padding` is re-read from config on every draw, but
    -- `cell_aspect` is cached into `images.scale.CELL_ASPECT` once at
    -- `setup()` time (see images.cell) — without this it would need a
    -- restart to take effect, unlike everything else calibration measures.
    require("images.cell").apply()
  end

  local function decline()
    notify().info("Not saved. For your own setup() spec:\ndisplay = { " .. summary:gsub("\n", ", ") .. " }")
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
  local function refresh_title()
    if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then return end
    local title, footer = labels()
    pcall(vim.api.nvim_win_set_config, state.win, { title = title, footer = footer })
  end

  local function nudge(d_row, d_col)
    return function()
      if not state then return end
      state.row = state.row + d_row
      state.col = state.col + d_col
      refresh_title()
      redraw()
    end
  end

  -- Step 0.01: fine enough to converge in a handful of presses across the
  -- range real fonts sit in (~0.4-0.6), coarse enough that a full rebuild per
  -- press (see regen_card) stays comfortable to hold a key through.
  local ASPECT_STEP = 0.01
  local function nudge_aspect(sign)
    return function()
      if not state then return end
      -- Rounded via string formatting rather than left as raw float
      -- arithmetic: repeated +/- 0.01 additions drift in binary floating
      -- point, and that drift would otherwise show up later as a spurious
      -- "changed" in offer_save's tolerance check.
      state.aspect = math.max(0.1, math.min(3, tonumber(("%.2f"):format(state.aspect + sign * ASPECT_STEP))))
      refresh_title()
      regen_card()
    end
  end

  local o = { buffer = buf, nowait = true, silent = true }

  ---@param keys string[]
  ---@param fn function
  ---@param desc string
  local function bind(keys, fn, desc)
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, fn, vim.tbl_extend("force", o, { desc = "images.calibrate: " .. desc }))
    end
  end

  bind({ "k", "<Up>" }, nudge(-1, 0), "move image up")
  bind({ "j", "<Down>" }, nudge(1, 0), "move image down")
  bind({ "h", "<Left>" }, nudge(0, -1), "move image left")
  bind({ "l", "<Right>" }, nudge(0, 1), "move image right")

  bind({ "+", "=" }, nudge_aspect(1), "widen cell aspect")
  bind({ "-" }, nudge_aspect(-1), "narrow cell aspect")

  bind({ "r" }, function()
    if not state then return end
    state.row, state.col = 0, 0
    state.aspect = require("images.cell").default()
    refresh_title()
    regen_card()
  end, "reset")

  bind({ "<CR>" }, function()
    if not state then return end
    local row, col, aspect = state.row, state.col, state.aspect
    teardown()
    -- Only ask once the window is gone: while the image is still on screen the
    -- dialog would paint over it (see the module docs).
    vim.schedule(function()
      offer_save(row, col, aspect)
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

  -- `images.scale.CELL_ASPECT` at this point already is the effective
  -- configured/calibrated value (`images.cell.apply()` ran during `setup()`),
  -- so the card starts out matching whatever aspect is currently in effect —
  -- correct if nothing needs it, a visible letterbox strip if it does.
  local aspect = require("images.scale").CELL_ASPECT
  local card, card_err = require("images.testcard").write(cols, rows, aspect)
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
    aspect = aspect,
    cols = cols,
    rows = rows,
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
