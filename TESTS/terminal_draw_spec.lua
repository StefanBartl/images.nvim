-- Test doubles: the cases below replace a module function for the length of
-- one case and put the original back straight after. LuaLS reads each of those
-- assignments as a second definition of a field that already has one -- which
-- is what a double is, not a mistake.
---@diagnostic disable: duplicate-set-field
-- TESTS/terminal_draw_spec.lua — the ordering of repaint and image output.
--
-- The image output itself needs a terminal with a graphics protocol and stays
-- unchecked headless (see run.lua). What is testable is the invariant `:Image
-- zen` once failed on: `nvim_ui_send` writes to the terminal immediately, while
-- Neovim's own repaint only runs once control returns to the main loop. Open a
-- window and draw into it in the same tick and the image goes out, after which
-- Neovim paints that window's empty cells over it — popup there, image gone.
--
-- Two things guard against that, and both are pinned down here:
--   1. `terminal.draw` forces the pending repaint BEFORE the payload goes out —
--      clearing away whatever was already queued before sending.
--   2. Every path that opens a window (`zen`, `hover_float`, `redact`) draws
--      only in the next tick — because no flush before sending can cover the
--      repaint that opening the window itself causes.
-- The ordering is what is checked, not the drawing.

---@param H table harness from TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")

  -- Without `nvim_ui_send` (API level < 14) there is no ordering to check.
  if not terminal.available() then return end

  --- Run `draw`/`draw_many` with its side effects recorded.
  ---@param fn fun()
  ---@return string[] log  "redraw" or "payload", in call order
  local function record(fn)
    local log = {}
    local real_send, real_cmd = vim.api.nvim_ui_send, vim.cmd
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then log[#log + 1] = "payload" end
    end
    vim.cmd = function(c, ...)
      if c == "redraw" then
        log[#log + 1] = "redraw"
        return
      end
      return real_cmd(c, ...)
    end
    local ok, err = pcall(fn)
    vim.api.nvim_ui_send, vim.cmd = real_send, real_cmd
    if not ok then error(err, 0) end
    return log
  end

  -- A tiny but real file: `draw` reads it before anything is sent — an
  -- unreadable path would bail out before the flush and never reach the
  -- ordering at all.
  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    H.write(img, "\137PNG\r\n\26\n-- not decodable, but not empty")

    -- ── A single image ──────────────────────────────────────────────────────
    local log = record(function()
      H.ok(terminal.draw(img, 1, 1, 10, 5), "draw reports success for a readable file")
    end)
    H.eq(#log, 2, "draw: exactly one flush and one payload")
    H.eq(log[1], "redraw", "draw: the repaint comes BEFORE the payload")
    H.eq(log[2], "payload", "draw: the payload comes after the repaint")

    -- ── A gallery ───────────────────────────────────────────────────────────
    log = record(function()
      local drawn = terminal.draw_many({
        { file = img, row = 1, col = 1, cols = 5, rows = 3 },
        { file = img, row = 1, col = 7, cols = 5, rows = 3 },
      })
      H.eq(drawn, 2, "draw_many draws both placements")
    end)
    H.eq(log[1], "redraw", "draw_many: the repaint comes BEFORE the first payload")
    H.eq(#log, 3, "draw_many: one flush for the whole block, not one per image")

    -- ── The failure case ────────────────────────────────────────────────────
    -- No payload, and no claim about a particular flush count: the point is that
    -- an unreadable path reports cleanly rather than sending.
    log = record(function()
      local ok = terminal.draw(dir .. "/does-not-exist.png", 1, 1, 10, 5)
      H.falsy(ok, "draw reports failure for a missing path")
    end)
    for _, entry in ipairs(log) do
      H.ok(entry ~= "payload", "a missing file sends no payload")
    end

    -- ── Window paths draw only in the next tick ─────────────────────────────
    -- The second half of the same cause: the flush above clears what was queued
    -- BEFORE sending -- not the repaint that opening the window itself causes.
    -- Create a window and draw in the same tick and you are still under
    -- Neovim's paint. So for `zen` (and equally `hover_float`/`redact`) nothing
    -- may have been sent yet once the call returns.
    local zen = require("images.zen")
    -- Without this the capability guard rightly reports an unrecognised terminal
    -- during the test run -- noise here, and the ordering does not depend on it.
    local prev_cfg = require("images.config").get()
    require("images.config").setup({ display = { assume_supported = true } })

    local sent = 0
    local real_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then sent = sent + 1 end
    end
    local ok_open, opened = pcall(zen.open, img)
    local immediate = sent
    vim.wait(500, function()
      return sent > 0
    end)
    local deferred = sent
    vim.api.nvim_ui_send = real_send
    pcall(zen.close)
    require("images.config").setup(prev_cfg)

    H.ok(ok_open and opened, "zen.open opens the window")
    H.eq(immediate, 0, "zen does NOT draw in the same tick as opening the window")
    H.eq(deferred, 1, "zen draws exactly once, as soon as the loop continues")
  end)
end
