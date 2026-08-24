-- TESTS/capability_spec.lua — the terminal capability check.
--
-- Detection only reads environment variables, so it is testable without a
-- terminal. What is checked above all is that it does *not* block hard, and
-- that the message contains a usable next step.

---@param H table harness from TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")

  -- Save the environment and restore it at the end, so the specs stay
  -- independent of one another.
  local saved = {}
  local keys = {
    "WEZTERM_EXECUTABLE",
    "WEZTERM_VERSION",
    "WEZTERM_PANE",
    "TERM_PROGRAM",
    "LC_TERMINAL",
    "KONSOLE_VERSION",
    "TMUX",
  }
  for _, k in ipairs(keys) do
    saved[k] = vim.env[k]
    vim.env[k] = nil
  end

  local function fresh(force)
    terminal.reset_capability()
    return terminal.capability(force)
  end

  -- ── Without any marker: not detected, but with a hint ────────────────────
  local cap = fresh(false)
  H.falsy(cap.ok, "an unknown terminal counts as unsupported")
  H.ok(cap.reason and #cap.reason > 0, "there is a reason")
  H.contains(cap.hint or "", "imgcat", "the hint names the concrete test")
  H.contains(cap.hint or "", "assume_supported", "…and the option that silences it")

  -- ── force skips detection ────────────────────────────────────────────────
  cap = fresh(true)
  H.ok(cap.ok, "assume_supported declares the terminal capable")

  -- ── WezTerm is detected by any of its variables ──────────────────────────
  for _, var in ipairs({ "WEZTERM_EXECUTABLE", "WEZTERM_VERSION", "WEZTERM_PANE" }) do
    vim.env[var] = "x"
    cap = fresh(false)
    H.ok(cap.ok, "WezTerm detected via " .. var)
    H.eq(cap.terminal, "WezTerm", "…and named")
    vim.env[var] = nil
  end

  -- ── iTerm2 via both of the usual variables ───────────────────────────────
  vim.env.TERM_PROGRAM = "iTerm.app"
  cap = fresh(false)
  H.eq(cap.terminal, "iTerm2", "iTerm2 via TERM_PROGRAM")
  vim.env.TERM_PROGRAM = nil

  vim.env.LC_TERMINAL = "iTerm2"
  cap = fresh(false)
  H.eq(cap.terminal, "iTerm2", "iTerm2 via LC_TERMINAL (survives SSH)")
  vim.env.LC_TERMINAL = nil

  -- ── tmux adds a hint, even for a recognised terminal ─────────────────────
  vim.env.WEZTERM_PANE = "0"
  vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
  cap = fresh(false)
  H.ok(cap.ok, "tmux does not make a capable terminal incapable")
  H.contains(cap.hint or "", "allow-passthrough", "…but the hint names the required tmux option")
  vim.env.TMUX = nil
  vim.env.WEZTERM_PANE = nil

  -- ── The result is memoized ───────────────────────────────────────────────
  terminal.reset_capability()
  vim.env.WEZTERM_PANE = "0"
  local first = terminal.capability(false)
  vim.env.WEZTERM_PANE = nil
  local second = terminal.capability(false)
  H.eq(first.terminal, second.terminal, "the result is memoized, not guessed again")

  for _, k in ipairs(keys) do
    vim.env[k] = saved[k]
  end
  terminal.reset_capability()
end
