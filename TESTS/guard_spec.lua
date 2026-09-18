-- TESTS/guard_spec.lua — images.guard: the shared "can this terminal draw at
-- all" check in front of every draw path (images.init/browse/zen), and its
-- warn-once-per-session behaviour.
--
-- `images.terminal.capability` itself only reads environment variables (see
-- capability_spec.lua) so this is testable the same way: no real terminal
-- needed. What guard.lua adds on top -- the `warned` flag that keeps the
-- capability warning from firing on every single draw -- is the part with
-- no coverage anywhere else, so it is what this spec exists for.
--
-- `lib.nvim.notify`'s `.create` is swapped for a spy rather than left alone:
-- guard.lua re-resolves it (`require(...).create(...)`) inside `M.check`
-- itself, so patching the *table field* after `images.guard` is already
-- loaded still takes effect on every subsequent call — no upvalue is holding
-- an old reference to work around.

---@param H table harness from TESTS/run.lua
return function(H)
  local guard = require("images.guard")
  local terminal = require("images.terminal")
  local notify_mod = require("lib.nvim.notify")

  local original_create = notify_mod.create
  local calls
  ---@diagnostic disable-next-line: duplicate-set-field
  notify_mod.create = function(_prefix)
    return {
      warn = function(msg)
        calls[#calls + 1] = { level = "warn", msg = msg }
      end,
      info = function(msg)
        calls[#calls + 1] = { level = "info", msg = msg }
      end,
      error = function(msg)
        calls[#calls + 1] = { level = "error", msg = msg }
      end,
    }
  end

  -- Same environment-variable set as capability_spec.lua, so this spec does
  -- not depend on whatever terminal it happens to run in.
  local saved = {}
  local keys =
    { "WEZTERM_EXECUTABLE", "WEZTERM_VERSION", "WEZTERM_PANE", "TERM_PROGRAM", "LC_TERMINAL", "KONSOLE_VERSION", "TMUX" }
  for _, k in ipairs(keys) do
    saved[k] = vim.env[k]
    vim.env[k] = nil
  end

  -- ── an unsupported terminal warns once, not on every check ───────────────
  calls = {}
  guard.reset()
  terminal.reset_capability()

  guard.check()
  H.eq(#calls, 1, "the first check on an unsupported terminal warns")

  guard.check()
  guard.check()
  H.eq(#calls, 1, "…and a second/third check in the same session does not warn again")

  -- ── reset() allows the warning again ──────────────────────────────────────
  guard.reset()
  guard.check()
  H.eq(#calls, 2, "reset() clears the warned flag, so the next check warns once more")

  -- ── a capable terminal with nothing to add stays silent ──────────────────
  calls = {}
  guard.reset()
  vim.env.WEZTERM_EXECUTABLE = "x"
  terminal.reset_capability()

  guard.check()
  H.eq(#calls, 0, "a recognised, capable terminal without a hint warns never")
  vim.env.WEZTERM_EXECUTABLE = nil

  -- ── a capable terminal WITH a hint (tmux) still warns once, then stops ────
  calls = {}
  guard.reset()
  vim.env.WEZTERM_PANE = "0"
  vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
  terminal.reset_capability()

  guard.check()
  H.eq(#calls, 1, "a capable terminal with a pending hint (tmux) still warns once")
  guard.check()
  H.eq(#calls, 1, "…and only once, same as the unsupported case")
  vim.env.TMUX = nil
  vim.env.WEZTERM_PANE = nil

  -- Restore: real notify, real environment, neutral guard/capability state.
  notify_mod.create = original_create
  for _, k in ipairs(keys) do
    vim.env[k] = saved[k]
  end
  guard.reset()
  terminal.reset_capability()
end
