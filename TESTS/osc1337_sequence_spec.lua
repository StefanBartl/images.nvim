---@diagnostic disable: duplicate-set-field
-- TESTS/osc1337_sequence_spec.lua -- the bytes of the OSC 1337 sequence.
--
-- terminal_draw_spec.lua pins the ORDER of repaint and payload and only looks for the substring
-- "1337". The sequence itself is the heart of the plugin, and a changed parameter would show up only
-- live. Here the complete string for a tiny known file is compared with one assembled independently
-- from the protocol, and the clipping of the box to the screen is checked.

---@param H table harness from TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")

  if not terminal.available() then return end

  local ESC, BEL = string.char(27), string.char(7)

  ---Draw `file` once with `nvim_ui_send` and `redraw` replaced, and return what was sent.
  ---@param file string
  ---@param row integer
  ---@param col integer
  ---@param cols integer
  ---@param rows integer
  ---@return string|nil sent
  local function sent_for(file, row, col, cols, rows)
    local sent
    local real_send, real_cmd, real_tmux = vim.api.nvim_ui_send, vim.cmd, vim.env.TMUX
    -- The bytes below are the unwrapped ones; the tmux envelope is pinned in terminal_draw_spec.lua.
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(s)
      sent = s
    end
    vim.cmd = function(c, ...)
      if c == "redraw" then return end
      return real_cmd(c, ...)
    end
    local ok, err = pcall(terminal.draw, file, row, col, cols, rows)
    vim.api.nvim_ui_send, vim.cmd, vim.env.TMUX = real_send, real_cmd, real_tmux
    if not ok then error(err, 0) end
    return sent
  end

  ---The sequence the protocol asks for, written out by hand.
  ---@param raw string
  ---@param row integer
  ---@param col integer
  ---@param cols integer
  ---@param rows integer
  ---@return string
  local function expected(raw, row, col, cols, rows)
    return ESC
      .. "[s"
      .. ESC
      .. "[?7l"
      .. ESC
      .. ("[%d;%dH"):format(row, col)
      .. ESC
      .. "]1337;File=inline=1;size="
      .. #raw
      .. ";width="
      .. cols
      .. ";height="
      .. rows
      .. ";preserveAspectRatio=1:"
      .. vim.base64.encode(raw)
      .. BEL
      .. ESC
      .. "[?7h"
      .. ESC
      .. "[u"
  end

  local saved_columns, saved_lines = vim.o.columns, vim.o.lines
  local function restore()
    vim.o.columns, vim.o.lines = saved_columns, saved_lines
  end

  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    local raw = "\137PNG\r\n\26\nbytes of a tiny image"
    H.write(img, raw)

    vim.o.columns, vim.o.lines = 120, 40

    -- ── The complete sequence for a box that fits ───────────────────────────────
    local sent = sent_for(img, 3, 7, 20, 10)
    H.eq(sent, expected(raw, 3, 7, 20, 10), "the full sequence: frame, position, parameters, base64, terminator")
    H.eq(sent:sub(1, 3), ESC .. "[s", "the cursor is saved first")
    H.eq(sent:sub(-3), ESC .. "[u", "and restored last")
    H.ok(sent:find(ESC .. "[?7l", 1, true) < sent:find(ESC .. "]1337", 1, true), "autowrap goes off before the payload")
    H.ok(sent:find(ESC .. "[?7h", 1, true) > sent:find(BEL, 1, true), "and back on after its terminator")
    H.ok(sent:find("size=" .. #raw .. ";", 1, true), "size is the byte length of the file, not of the base64")

    -- ── The box is clipped to the screen ────────────────────────────────────────
    -- 120 columns: from column 111 only 10 cells remain. 40 lines: from row 30 one row stays free
    -- (inline=1 moves the cursor down by the image height; ending on the last row would scroll).
    sent = sent_for(img, 30, 111, 50, 50)
    H.eq(sent, expected(raw, 30, 111, 10, 10), "width and height are cut to what is left, one row kept free")

    -- ── Positions below 1 are lifted to 1 ───────────────────────────────────────
    sent = sent_for(img, -2, 0, 5, 5)
    H.eq(sent, expected(raw, 1, 1, 5, 5), "a negative padding never reaches the cursor position")

    -- ── The box never collapses to nothing ──────────────────────────────────────
    sent = sent_for(img, 40, 120, 9, 9)
    H.eq(sent, expected(raw, 40, 120, 1, 1), "at the last cell the box is one cell, not zero")
  end)

  restore()
end
