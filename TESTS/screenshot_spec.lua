-- TESTS/screenshot_spec.lua — availability detection for `:Image screenshot`.
--
-- Only `available()`/`unavailable_reason()` are covered here: pure queries of
-- `vim.fn.has`/`executable`, without triggering a real capture. The capture
-- path itself launches an external, interactive tool (Snipping
-- Tool/screencapture/grim+slurp/maim) and therefore cannot be automated
-- meaningfully — neither headless nor without a human at the mouse. The same
-- boundary as the real download in images.remote, likewise only verified
-- manually rather than committed.

---@param H table harness from TESTS/run.lua
return function(H)
  local screenshot = require("images.screenshot")

  -- `available()` must run through cleanly whatever the actual result -- on
  -- every platform the suite runs on (here: the CI platform or the local
  -- machine), not only the one the concrete result applies to.
  local ok, available = pcall(screenshot.available)
  H.ok(ok, "available() does not throw: " .. tostring(available))
  H.ok(type(available) == "boolean", "available() returns a boolean")

  if not available then
    local ok2, reason = pcall(screenshot.unavailable_reason)
    H.ok(ok2, "unavailable_reason() does not throw: " .. tostring(reason))
    H.ok(type(reason) == "string" and #reason > 0, "…and returns a non-empty reason")
  end

  -- On Windows it is always available (ms-screenclip: ships with the system, no
  -- separate tool needed) -- the one case that can be checked unambiguously
  -- without mocking the platform.
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    H.ok(available, "always available on Windows (ms-screenclip: needs no external tool)")

    -- ── The Windows poll timeout must fire even when a single clipboard
    --    read never completes (ERR-03 follow-up) ──────────────────────────
    --
    -- `vim.system` is stubbed here rather than left real: the actual capture
    -- launches the interactive Snipping Tool UI and needs a human at the
    -- mouse (see this file's header), but the polling *logic* around it --
    -- the timer, the `pending`/`elapsed`/`done` bookkeeping in
    -- `capture_windows` -- is plain async plumbing with no UI in it at all,
    -- and is exactly what regressed: a `pending` guard that let a single
    -- hung clipboard-read process (e.g. blocked by AV/EDR hooking a `-STA`
    -- PowerShell start) freeze `elapsed` forever, so the configured timeout
    -- never fired and `:Image screenshot` hung silently with no way out but
    -- restarting Neovim. This reproduces exactly that: the first poll tick's
    -- read never invokes its callback, and the timeout must still fire.
    local original_system = vim.system
    local original_setup = vim.deepcopy(require("images.config").user_opts())

    require("images.config").setup({
      display = { screenshot = { windows_timeout_ms = 30, windows_poll_interval_ms = 5 } },
    })

    local powershell_calls = 0
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, on_exit)
      if cmd[1] == "explorer.exe" then
        vim.schedule(function()
          on_exit({ code = 0, stdout = "", stderr = "" })
        end)
      elseif cmd[1] == "powershell.exe" then
        powershell_calls = powershell_calls + 1
        if powershell_calls == 1 then
          -- The baseline read, before the Snipping Tool is even launched:
          -- answer promptly with "no image in the clipboard".
          vim.schedule(function()
            on_exit({ code = 0, stdout = "", stderr = "" })
          end)
        end
        -- Every later call is a poll tick's read -- `on_exit` is deliberately
        -- never invoked, simulating the hung PowerShell process.
      end
      return {
        pid = -1,
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local finished, capture_ok, capture_err = false, nil, nil
    local out = vim.fn.tempname() .. ".png"
    screenshot.capture(out, function(cb_ok, cb_err)
      finished, capture_ok, capture_err = true, cb_ok, cb_err
    end)

    -- Comfortably above windows_timeout_ms (30ms); under the pre-fix code
    -- this never becomes true and vim.wait exhausts its own budget instead.
    vim.wait(1000, function()
      return finished
    end, 10)

    vim.system = original_system
    require("images.config").setup(original_setup) -- restore for later specs

    H.ok(finished, "the timeout still fires even though one clipboard read never completes")
    H.falsy(capture_ok, "…reporting failure, not a silent hang")
    H.contains(capture_err or "", "timed out", "…specifically the timeout, not some other error")
    H.ok(powershell_calls >= 1, "sanity: the stub was actually exercised")
  end
end
