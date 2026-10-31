-- TESTS/xtversion_spec.lua — the XTVERSION probe and how its answer refines
-- the environment heuristic in images.terminal.capability.
--
-- The probe itself needs a UI to send to; the spec stubs `nvim_list_uis` and
-- `nvim_ui_send` and feeds the replies the way `TermResponse` would.

---@param H table harness from TESTS/run.lua
return function(H)
  local xtversion = require("images.xtversion")
  local terminal = require("images.terminal")

  -- The reply measured in WezTerm on Windows (see images.xtversion).
  local WEZTERM = "\27P>|WezTerm 20240203-110809-5046fc22"

  -- ── parse ────────────────────────────────────────────────────────────────
  local a = xtversion.parse(WEZTERM)
  H.ok(a, "the measured WezTerm reply parses")
  H.eq(a and a.name, "WezTerm", "...name")
  H.eq(a and a.version, "20240203-110809-5046fc22", "...version")
  H.eq(a and a.terminal, "WezTerm", "...matched against the list")
  H.eq(a and a.osc1337, true, "...which speaks OSC 1337")

  a = xtversion.parse("\27P>|kitty(0.35.2)\27\\")
  H.eq(a and a.terminal, "kitty", "`name(version)` with a terminator parses")
  H.eq(a and a.version, "0.35.2", "...version without the parentheses")
  H.eq(a and a.osc1337, false, "...and kitty does not speak OSC 1337")

  a = xtversion.parse("\27P>|iTerm2 3.5.0")
  H.eq(a and a.terminal, "iTerm2", "iTerm2 matched")

  a = xtversion.parse("\27P>|Rio 0.2.1")
  H.eq(a and a.name, "Rio", "an unlisted terminal still parses")
  H.eq(a and a.terminal, nil, "...but is not matched")
  H.eq(a and a.osc1337, nil, "...and has no verdict")

  a = xtversion.parse("\27P>|xterm.js(5.3.0)")
  H.eq(a and a.name, "xterm.js", "xterm.js (VS Code) parses")
  H.eq(a and a.terminal, nil, "...but is not XTerm: names match exactly, not by prefix")
  H.eq(a and a.osc1337, nil, "...and has no verdict")

  a = xtversion.parse("\27P>|XTerm(390)")
  H.eq(a and a.terminal, "XTerm", "XTerm itself still matches")

  a = xtversion.parse("\27P>|tmux 3.4")
  H.ok(a and a.tmux, "tmux answering for itself is recognised")

  H.eq(xtversion.parse("\27[?61;6;7;22;23;24;28;32;42c"), nil, "a DA1 reply is not XTVERSION")
  H.eq(xtversion.parse("\27P1$r0m\27\\"), nil, "another DCS reply is not XTVERSION")
  H.eq(xtversion.parse(nil), nil, "nil is not a reply")

  -- ── start: headless sends nothing ────────────────────────────────────────
  xtversion.reset()
  H.falsy(xtversion.start(), "no UI attached: nothing is sent")
  H.eq(xtversion.status().state, "skipped", "...state skipped")
  H.contains(xtversion.status().why or "", "no UI", "...with the reason")

  -- With a (stubbed) UI the query goes out once and the reply is consumed.
  local real_uis, real_send = vim.api.nvim_list_uis, vim.api.nvim_ui_send
  local sent = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_list_uis = function()
    return { { rgb = true } }
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_ui_send = function(s)
    sent[#sent + 1] = s
  end
  local function with_ui(fn)
    local ok, err = pcall(fn)
    vim.api.nvim_list_uis, vim.api.nvim_ui_send = real_uis, real_send
    if not ok then error(err, 0) end
  end

  with_ui(function()
    xtversion.reset()
    -- Under tmux the query is not sent; tmux is asked instead (stubbed).
    local real_system = vim.system
    local calls = {}
    local system_fails = false
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(argv, _, on_exit)
      if system_fails then error("ENOENT: no such file or directory (cmd): 'tmux'") end
      calls[#calls + 1] = { argv = argv, on_exit = on_exit }
      return {}
    end
    local TMUX_ENV = { TMUX = "/tmp/tmux-1/default,1,0", TMUX_PANE = "%3" }
    --- Start under the stubbed tmux and let it print `stdout` with exit `code`.
    local function tmux_says(code, stdout)
      xtversion.reset()
      calls = {}
      local started = xtversion.start(TMUX_ENV)
      if calls[1] then calls[1].on_exit({ code = code, stdout = stdout, stderr = "" }) end
      vim.wait(1000, function()
        return xtversion.status().state ~= "pending"
      end)
      return started
    end
    local ok_tmux, err_tmux = pcall(function()
      local before = #sent
      H.ok(tmux_says(0, "WezTerm 20240203-110809-5046fc22\n"), "under tmux tmux is asked")
      H.eq(#sent, before, "...and nothing is sent to the terminal")
      H.eq(
        calls[1] and table.concat(calls[1].argv, " "),
        "tmux display-message -p -t %3 #{client_termtype}",
        "...for this pane's client_termtype"
      )
      local st = xtversion.status()
      H.eq(st.state, "answered", "tmux's record of the outer terminal answers the probe")
      H.eq(st.answer and st.answer.terminal, "WezTerm", "...naming the outer terminal")
      H.eq(st.answer and st.answer.via, "tmux", "...read through tmux")
      H.falsy(st.answer and st.answer.tmux, "...not tmux answering for itself")

      tmux_says(0, "\n")
      H.eq(xtversion.status().state, "skipped", "an empty client_termtype: skipped")
      H.contains(xtversion.status().why or "", "client_termtype", "...and the reason names the format")

      tmux_says(1, "")
      H.eq(xtversion.status().state, "skipped", "tmux failing: skipped")
      H.contains(xtversion.status().why or "", "failed", "...and the reason says so")

      tmux_says(0, "tmux 3.4\n")
      H.ok(xtversion.status().answer and xtversion.status().answer.tmux, "a nested tmux is recognised as tmux")

      system_fails = true
      H.falsy(tmux_says(0, ""), "tmux not runnable: nothing started")
      H.contains(xtversion.status().why or "", "could not be run", "...and the reason says so")
      system_fails = false

      -- A late tmux result from an earlier probe must not answer a later one.
      xtversion.reset()
      calls = {}
      xtversion.start(TMUX_ENV)
      local stale_exit = calls[1].on_exit
      xtversion.reset()
      xtversion.start(TMUX_ENV)
      stale_exit({ code = 0, stdout = "kitty(0.35.2)", stderr = "" })
      vim.wait(100, function()
        return false
      end)
      H.eq(xtversion.status().state, "pending", "a stale tmux result is dropped")
      xtversion.reset()
    end)
    vim.system = real_system
    if not ok_tmux then error(err_tmux, 0) end

    xtversion.reset()
    local heard
    local stale = 0
    xtversion.on_answer("spec", function()
      stale = stale + 1
    end)
    xtversion.on_answer("spec", function(ans)
      heard = ans
    end)
    H.ok(xtversion.start({}), "with a UI the query is sent")
    H.eq(sent[#sent], "\27[>q", "...as XTVERSION")
    H.eq(xtversion.status().state, "pending", "...and the probe is pending")
    H.falsy(xtversion.start({}), "a second start while pending sends nothing more")
    H.eq(#sent, 1, "...exactly one query")

    -- Through the real autocmd, as Neovim would deliver it.
    vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = "\27[?62c" } })
    H.eq(xtversion.status().state, "pending", "an unrelated reply leaves it pending")
    vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = WEZTERM } })
    H.eq(xtversion.status().state, "answered", "the XTVERSION reply answers it")
    H.eq(heard and heard.terminal, "WezTerm", "...and listeners hear about it")
    H.eq(stale, 0, "...a listener registered again under the same key replaces the old one")
    local late = 0
    xtversion.on_answer("late", function()
      late = late + 1
    end)
    H.eq(late, 1, "a listener added after the answer hears it right away")
    xtversion.on_answer("late", nil)
    H.falsy(xtversion.on_response("\27P>|kitty(1)"), "a later reply is ignored")
    H.eq(xtversion.status().answer.terminal, "WezTerm", "...the first answer stands")
  end)

  -- A timeout armed by an earlier probe must not end a later one.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_ui_send = function() end
  with_ui(function()
    local real_timeout = xtversion.TIMEOUT_MS
    xtversion.TIMEOUT_MS = 50
    xtversion.reset()
    xtversion.start({})
    xtversion.reset()
    xtversion.TIMEOUT_MS = 100000
    xtversion.start({})
    xtversion.TIMEOUT_MS = real_timeout
    vim.wait(300, function()
      return false
    end)
    H.eq(xtversion.status().state, "pending", "an old probe's timeout leaves the new probe pending")
    H.ok(xtversion.on_response(WEZTERM), "...so its reply is still heard")
    xtversion.reset()
  end)

  -- ── capability: the reply refines the environment ────────────────────────
  local keys = {
    "WEZTERM_EXECUTABLE",
    "WEZTERM_VERSION",
    "WEZTERM_PANE",
    "TERM_PROGRAM",
    "LC_TERMINAL",
    "KONSOLE_VERSION",
    "KITTY_LISTEN_ON",
    "WT_SESSION",
    "TMUX",
    -- lib.nvim detects Kitty from TERM too; a suite run inside kitty would
    -- otherwise see a Kitty environment.
    "TERM",
  }
  local saved = {}
  for _, k in ipairs(keys) do
    saved[k] = vim.env[k]
    vim.env[k] = nil
  end

  --- Capability with the given reply (nil = none) and environment.
  ---@param reply string|nil
  ---@param env table<string, string>|nil
  ---@param force boolean|nil
  local function cap_with(reply, env, force)
    xtversion.reset()
    if reply then
      with_ui(function()
        xtversion.start({})
        xtversion.on_response(reply)
      end)
      vim.api.nvim_list_uis, vim.api.nvim_ui_send = real_uis, real_send
    end
    for k, v in pairs(env or {}) do
      vim.env[k] = v
    end
    terminal.reset_capability()
    local cap = terminal.capability(force)
    for k in pairs(env or {}) do
      vim.env[k] = nil
    end
    return cap
  end

  -- Re-stub for cap_with's with_ui (it restores the real functions each time).
  local function stubbed_cap(reply, env, force)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return { {} }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_ui_send = function() end
    return cap_with(reply, env, force)
  end

  local cap = stubbed_cap(nil, nil)
  H.falsy(cap.ok, "no variable, no reply: not recognised")

  cap = stubbed_cap(WEZTERM, nil)
  H.ok(cap.ok, "no variable (e.g. over SSH), but WezTerm answered: ok")
  H.eq(cap.terminal, "WezTerm", "...named from the reply")
  H.eq(cap.source, "terminal", "...and the source says so")
  H.eq(cap.conflict, nil, "...without a conflict")

  cap = stubbed_cap(nil, { WEZTERM_PANE = "0" })
  H.eq(cap.source, "environment", "only the variable: the environment decides")

  cap = stubbed_cap(WEZTERM, { WEZTERM_PANE = "0" })
  H.eq(cap.source, "terminal", "variable and reply agree: the reply decides")
  H.eq(cap.conflict, nil, "...and nothing conflicts")

  cap = stubbed_cap("\27P>|kitty(0.35.2)", { WEZTERM_PANE = "0" })
  H.falsy(cap.ok, "inherited WezTerm variable inside kitty: the reply wins")
  H.contains(cap.reason or "", "kitty", "...the reason names the answer")
  H.contains(cap.conflict or "", "WezTerm", "...and the conflict names both")
  H.contains(cap.conflict or "", "kitty", "...both")

  cap = stubbed_cap("\27P>|kitty(0.35.2)", { WEZTERM_PANE = "0" }, true)
  H.ok(cap.ok, "assume_supported still overrides a negative reply")
  H.eq(cap.source, "assumed", "...as assumed")
  H.eq(cap.terminal, nil, "...without naming kitty as a capable terminal")

  cap = stubbed_cap("\27P>|kitty(0.35.2)", { KITTY_LISTEN_ON = "unix:/tmp/kitty" })
  H.eq(cap.conflict, nil, "environment `Kitty` and reply `kitty` agree: no conflict")
  cap = stubbed_cap("\27P>|kitty(0.35.2)", { TERM = "xterm-kitty" })
  H.eq(cap.conflict, nil, "...also when TERM names kitty")

  cap = stubbed_cap("\27P>|Rio 0.2.1", { WEZTERM_PANE = "0" })
  H.eq(cap.source, "environment", "an unlisted reply has no opinion: the environment decides")
  H.ok(cap.ok, "...and stays ok")
  H.eq(cap.reply, "Rio 0.2.1", "...the reply is still reported")

  cap = stubbed_cap("\27P>|Rio 0.2.1", nil)
  H.falsy(cap.ok, "unlisted reply, no variable: not recognised")
  H.contains(cap.reason or "", "Rio", "...and the reason names what answered")

  -- ── describe: what `:Image check` and `:checkhealth` print ───────────────
  cap = stubbed_cap(WEZTERM, nil)
  local text = terminal.describe(cap, xtversion.status())
  H.contains(text, "terminal's own reply", "describe names the reply as the source")
  H.contains(text, "WezTerm 20240203", "...with the reply text")
  H.falsy(text:find("not on the list", 1, true), "...and does not call a listed reply unlisted")

  cap = stubbed_cap("\27P>|kitty(0.35.2)", nil, true)
  text = terminal.describe(cap, xtversion.status())
  H.contains(text, "assume_supported", "assumed over a listed negative reply: describe says so")
  H.contains(text, "listed", "...calls the reply listed")
  H.falsy(text:find("not on the list", 1, true), "...not unlisted")
  H.falsy(text:find("environment decides", 1, true), "...and does not credit the environment")

  text = terminal.describe(cap, { state = "answered", answer = xtversion.parse("\27P>|tmux 3.4") })
  H.contains(text, "tmux answered", "a tmux reply is named as tmux answering for itself")
  H.falsy(text:find("not on the list", 1, true), "...not as an unlisted terminal")

  cap = stubbed_cap("\27P>|Rio 0.2.1", { WEZTERM_PANE = "0" })
  text = terminal.describe(cap, xtversion.status())
  H.contains(text, "not on the list", "an unlisted reply is called unlisted")

  -- Under tmux: the outer terminal's reply as tmux recorded it decides, and
  -- `:Image check` names tmux as where it came from.
  local via = xtversion.parse(WEZTERM)
  via.via = "tmux"
  cap = { ok = true, terminal = "WezTerm", source = "terminal", reply = via.raw, reply_via = "tmux" }
  text = terminal.describe(cap, { state = "answered", answer = via })
  H.contains(text, "client_termtype", "a reply read through tmux names client_termtype as the source")
  H.contains(text, "WezTerm 20240203", "...with the reply text")
  via = xtversion.parse("\27P>|Rio 0.2.1")
  via.via = "tmux"
  text = terminal.describe({ ok = false }, { state = "answered", answer = via })
  H.contains(text, "tmux reports the outer terminal", "an unlisted reply through tmux says tmux reported it")
  via = xtversion.parse("\27P>|tmux 3.4")
  via.via = "tmux"
  text = terminal.describe({ ok = false }, { state = "answered", answer = via })
  H.contains(text, "nested tmux", "a tmux reported by tmux is a nested tmux")

  -- capability carries where the reply came from.
  xtversion.reset()
  local real_system = vim.system
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(_, _, on_exit)
    on_exit({ code = 0, stdout = "WezTerm 20240203-110809-5046fc22\n", stderr = "" })
    return {}
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  local ok_cap, err_cap = pcall(function()
    xtversion.start({ TMUX = "/tmp/tmux-1/default,1,0" })
    vim.wait(1000, function()
      return xtversion.status().state ~= "pending"
    end)
    terminal.reset_capability()
    cap = terminal.capability(false)
    H.eq(cap.source, "terminal", "the reply read through tmux decides the capability")
    H.eq(cap.reply_via, "tmux", "...and the capability says it came through tmux")
  end)
  vim.system, vim.api.nvim_list_uis = real_system, real_uis
  if not ok_cap then error(err_cap, 0) end

  cap = stubbed_cap(nil, { WEZTERM_PANE = "0" })
  text = terminal.describe(cap, { state = "silent" })
  H.contains(text, "detected from the environment", "describe names the environment as the source")
  H.contains(text, "did not answer", "...and that the terminal stayed silent")
  text = terminal.describe(cap, { state = "pending" })
  H.contains(text, "pending", "a pending probe is said to be pending")

  -- ── setup wires the answer to the memo ───────────────────────────────────
  -- A capability memoized before the reply must not outlive it.
  xtversion.reset()
  vim.api.nvim_list_uis, vim.api.nvim_ui_send = real_uis, real_send
  require("images").setup({ deps_popup = false })
  terminal.reset_capability()
  H.falsy(terminal.capability(false).ok, "before the reply: not recognised (memoized)")
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_ui_send = function() end
  with_ui(function()
    xtversion.start({})
  end)
  xtversion.on_response(WEZTERM)
  H.ok(terminal.capability(false).ok, "after the reply the memo is dropped and WezTerm counts")

  xtversion.reset()
  terminal.reset_capability()
  for _, k in ipairs(keys) do
    vim.env[k] = saved[k]
  end
end
