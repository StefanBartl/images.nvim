-- TESTS/anchor_spec.lua — the canonical "draw an image in a window" place.
--
-- `resolve_window` is testable with real windows and buffers, without a
-- terminal. The drawing proper needs a graphics protocol and stays unchecked
-- (see run.lua) — what is checked instead is the same invariant as in
-- terminal_draw_spec.lua: whether and when `nvim_ui_send` is called at all, via
-- a mock, not the actual drawing.

---@param H table harness from TESTS/run.lua
return function(H)
  local anchor = require("images.anchor")

  -- ── resolve_window: nil/0 -> the current window ──────────────────────────
  local current = vim.api.nvim_get_current_win()
  H.eq(anchor.resolve_window(nil), current, "nil resolves to the current window")
  H.eq(anchor.resolve_window(0), current, "0 resolves to the current window")

  -- ── resolve_window: a valid window handle stays unchanged ────────────────
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  local other_win = vim.api.nvim_open_win(scratch_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 10,
    height = 5,
  })
  H.eq(anchor.resolve_window(other_win), other_win, "a valid window handle stays unchanged")

  -- ── resolve_window: a buffer the current window shows ────────────────────
  local cur_buf = vim.api.nvim_win_get_buf(current)
  H.eq(anchor.resolve_window(cur_buf), current, "the current window's buffer resolves to that window")

  -- ── resolve_window: a buffer only ANOTHER window shows ───────────────────
  H.eq(anchor.resolve_window(scratch_buf), other_win, "another window's buffer resolves to that window")

  -- ── resolve_window: a buffer with no window at all ───────────────────────
  local orphan_buf = vim.api.nvim_create_buf(false, true)
  local win2, err2 = anchor.resolve_window(orphan_buf)
  H.eq(win2, nil, "a buffer without a window yields no result")
  H.contains(err2 or "", tostring(orphan_buf), "…the error message names the buffer")

  -- ── resolve_window: neither a window nor a buffer ────────────────────────
  local win3, err3 = anchor.resolve_window(999999)
  H.eq(win3, nil, "an invalid handle yields no result")
  H.ok(err3 ~= nil, "…with an error message")

  pcall(vim.api.nvim_win_close, other_win, true)
  pcall(vim.api.nvim_buf_delete, scratch_buf, { force = true })
  pcall(vim.api.nvim_buf_delete, orphan_buf, { force = true })

  -- Without `nvim_ui_send` (API level < 14) there is nothing to count — the
  -- same restraint as terminal_draw_spec.lua.
  if not require("images.terminal").available() then return end

  -- ── draw(): an unknown position fails without drawing ────────────────────
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- not decodable, but not empty")

    local sent = 0
    local real_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then sent = sent + 1 end
    end

    local done_ok, done_err
    local ok, err = anchor.draw(nil, "nowhere", img, {
      on_done = function(o, e)
        done_ok, done_err = o, e
      end,
    })
    H.falsy(ok, "an unknown position reports failure")
    H.ok(err ~= nil, "…with an error message")
    H.eq(sent, 0, "…and sends nothing")
    H.eq(done_ok, false, "on_done runs synchronously with the same result")
    H.eq(done_err, err, "…and the same error message")

    -- ── draw(): without defer it sends immediately ──────────────────────────
    sent = 0
    ok = anchor.draw(nil, "full", img)
    H.ok(ok, "draw without defer reports success for a readable file")
    H.eq(sent, 1, "…and sends at once, without waiting for the next tick")

    -- ── draw(): with defer it sends only in the next tick ───────────────────
    sent = 0
    done_ok = nil
    local accepted = anchor.draw(nil, "full", img, {
      defer = true,
      on_done = function(o)
        done_ok = o
      end,
    })
    H.ok(accepted, "defer=true reports 'accepted' immediately")
    H.eq(sent, 0, "…but sends nothing yet in the same tick")
    vim.wait(500, function()
      return sent > 0
    end)
    H.eq(sent, 1, "…only once the loop continues")
    H.eq(done_ok, true, "on_done reports success afterwards")

    vim.api.nvim_ui_send = real_send
    require("images.terminal").clear()
  end)

  -- ── draw(): the border indents the draw position, not the size ───────────
  -- A regression test for the offset a bordered hover float showed:
  -- `nvim_win_get_position` is unchanged by a border (still the border's OUTER
  -- edge), so `draw_now` itself has to indent by one border segment. Checked
  -- via the coordinates actually passed to `images.terminal.draw` rather than
  -- the bytes sent — the values are what matters here, not the protocol.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- not decodable, but not empty")

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "", "", "", "", "" })

    ---@param border string|table
    ---@return { row: integer, col: integer }
    local function draw_into(border)
      local win = vim.api.nvim_open_win(scratch, false, {
        relative = "editor",
        row = 10,
        col = 10,
        width = 10,
        height = 5,
        style = "minimal",
        border = border,
        focusable = false,
        noautocmd = true,
      })

      local captured
      local real_draw = require("images.terminal").draw
      require("images.terminal").draw = function(_file, row, col, cols, rows)
        captured = { row = row, col = col, cols = cols, rows = rows }
        return true
      end

      anchor.draw(win, "full", img, { inset = 0 })
      require("images.terminal").draw = real_draw
      vim.api.nvim_win_close(win, true)
      return captured
    end

    local none = draw_into("none")
    H.eq(none.row, 11, "no border: row = pos+1, no offset")
    H.eq(none.col, 11, "no border: col = pos+1, no offset")

    local rounded = draw_into("rounded")
    H.eq(rounded.row, 12, "rounded: row additionally indented by the top border segment")
    H.eq(rounded.col, 12, "rounded: col additionally indented by the left border segment")

    local top_only = draw_into({ "", "-", "", "", "", "", "", "" })
    H.eq(top_only.row, 12, "top border only: row indents")
    H.eq(top_only.col, 11, "top border only: col stays unchanged (no left segment)")

    vim.api.nvim_buf_delete(scratch, { force = true })
  end)

  -- ── draw(): display.terminal_padding adds a fixed cell offset ────────────
  -- Compensation for terminals whose OSC 1337 placement does not account for
  -- their own window_padding (see anchor.lua's terminal_padding()). The default
  -- {0,0} must be a no-op — unconfigured, nothing may change for any existing
  -- caller.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- not decodable, but not empty")

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "", "", "", "", "" })
    local win = vim.api.nvim_open_win(scratch, false, {
      relative = "editor",
      row = 10,
      col = 10,
      width = 10,
      height = 5,
      style = "minimal",
      border = "none",
      focusable = false,
      noautocmd = true,
    })

    local captured
    local real_draw = require("images.terminal").draw
    require("images.terminal").draw = function(_file, row, col, cols, rows)
      captured = { row = row, col = col, cols = cols, rows = rows }
      return true
    end

    local prev_conf = require("images.config").get()

    require("images.config").setup({})
    anchor.draw(win, "full", img, { inset = 0 })
    H.eq(captured.row, 11, "without a terminal_padding configuration: no offset")
    H.eq(captured.col, 11, "without a terminal_padding configuration: no offset")

    require("images.config").setup({ display = { terminal_padding = { row = 2, col = 1 } } })
    anchor.draw(win, "full", img, { inset = 0 })
    H.eq(captured.row, 13, "terminal_padding.row adds to the row")
    H.eq(captured.col, 12, "terminal_padding.col adds to the column")

    -- ── opts.padding overrides the configuration without changing it ────────
    -- `images.calibrate` tries values out. Doing that through `config.setup`
    -- would leave the user's remaining configuration overwritten — exactly how
    -- `cell_aspect` was lost in the first version. So the value has to ride on
    -- the call, not on the state.
    require("images.config").setup({ display = { cell_aspect = 0.46, terminal_padding = { row = 2, col = 1 } } })
    anchor.draw(win, "full", img, { inset = 0, padding = { row = -3, col = 0 } })
    H.eq(captured.row, 8, "opts.padding beats display.terminal_padding")
    H.eq(captured.col, 11, "…on both axes, even when only one is set")
    H.eq(require("images.config").get().display.cell_aspect, 0.46, "…and leaves the rest of the configuration untouched")
    H.eq(require("images.config").get().display.terminal_padding.row, 2, "…including the configured terminal_padding")

    require("images.config").setup(prev_conf)
    require("images.terminal").draw = real_draw
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)

  -- ── draw(): display.draw_inset keeps a margin free all round ─────────────
  -- Toleranz gegen Sub-Zellen-Versatz auf Terminals mit nicht
  -- zell-ausgerichtetem Fenster-Padding (siehe anchor.lua's draw_inset).
  -- Both are checked: that the margin takes effect, and that a caller can opt
  -- out of it explicitly — images.redact depends on exactly that.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- not decodable, but not empty")

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "", "", "", "", "" })
    local win = vim.api.nvim_open_win(scratch, false, {
      relative = "editor",
      row = 10,
      col = 10,
      width = 20,
      height = 10,
      style = "minimal",
      border = "none",
      focusable = false,
      noautocmd = true,
    })

    local captured
    local real_draw = require("images.terminal").draw
    require("images.terminal").draw = function(_file, row, col, cols, rows)
      captured = { row = row, col = col, cols = cols, rows = rows }
      return true
    end

    local prev_conf = require("images.config").get()

    require("images.config").setup({ display = { draw_inset = 0 } })
    anchor.draw(win, "full", img)
    H.eq(captured.cols, 20, "draw_inset = 0: the box fills the window width")
    H.eq(captured.rows, 10, "draw_inset = 0: the box fills the window height")
    H.eq(captured.row, 11, "draw_inset = 0: no offset")
    H.eq(captured.col, 11, "draw_inset = 0: no offset")

    require("images.config").setup({ display = { draw_inset = 1 } })
    anchor.draw(win, "full", img)
    H.eq(captured.cols, 18, "draw_inset = 1: the box is one cell narrower per side")
    H.eq(captured.rows, 8, "draw_inset = 1: the box is one cell shorter per side")
    H.eq(captured.row, 12, "draw_inset = 1: the box stays centred, the start row indents")
    H.eq(captured.col, 12, "draw_inset = 1: the box stays centred, the start column indents")

    -- The caller beats the configuration — which is why images.redact keeps
    -- drawing flush whatever the global setting says.
    anchor.draw(win, "full", img, { inset = 0 })
    H.eq(captured.cols, 20, "an explicit inset = 0 overrides the configuration")
    H.eq(captured.row, 11, "an explicit inset = 0 draws flush again")

    -- A margin that would eat the image entirely is capped.
    require("images.config").setup({ display = { draw_inset = 99 } })
    anchor.draw(win, "full", img)
    H.ok(captured.cols >= 1, "an oversized margin leaves at least one column of image")
    H.ok(captured.rows >= 1, "an oversized margin leaves at least one row of image")

    require("images.config").setup(prev_conf)
    require("images.terminal").draw = real_draw
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)
end
