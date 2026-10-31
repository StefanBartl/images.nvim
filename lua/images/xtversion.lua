---@module 'images.xtversion'
---@brief Ask the terminal its name with XTVERSION (`CSI > q`).
---@description
--- OSC 1337 has no capability query, but the terminal can be asked who it is:
--- XTVERSION is answered with a DCS string (`ESC P >| name version ESC \`), and
--- Neovim forwards DCS replies to Lua through the `TermResponse` autocmd
--- (`:h TermResponse`). CSI replies (cursor position, cell size) are not
--- forwarded, which is why this is the only query of its kind the plugin
--- sends.
---
--- Measured on 2026-10-31: WezTerm 20240203 on Windows (ConPTY), Neovim 0.12.2,
--- the query sent with `nvim_ui_send` from `UIEnter` came back as
--- `ESC P >|WezTerm 20240203-110809-5046fc22` within the first redraw.
---
--- The answer refines the environment heuristic in `images.terminal`; it never
--- replaces it. The environment is read synchronously before the first draw,
--- the answer arrives asynchronously some milliseconds later, and a terminal
--- that does not implement XTVERSION simply never answers (`silent`).
---
--- Not under tmux: tmux answers XTVERSION itself (`tmux 3.4`), so the reply
--- names the multiplexer rather than the terminal, and with `extended-keys` on
--- the reply leaks into the buffer as typed text instead of reaching
--- `TermResponse` (folke/snacks.nvim#2332).

local M = {}

--- The query: XTVERSION, "report terminal name and version".
M.QUERY = "\27[>q"

--- How long to wait for an answer before declaring the terminal silent.
--- A terminal that implements XTVERSION answers within one round trip; the
--- margin covers SSH latency.
M.TIMEOUT_MS = 1500

---@class Images.XtversionEntry
---@field name string canonical name, shown to the user
---@field match string the reply's name part, lowercased (matched exactly)
---@field osc1337 boolean whether it draws OSC 1337 inline images
---@field evidence string why the entry is here

--- Terminals the reply is matched against, by the reply's whole name part
--- (lowercased). Exact, not a prefix: `xterm.js(5.3.0)` (VS Code and other
--- Electron terminals) must not count as XTerm. Only terminals with evidence for OSC 1337 are marked
--- `osc1337 = true`; an unlisted name has no opinion and leaves the decision
--- to the environment. Rio, Warp, Tabby and Hyper are deliberately absent:
--- neither their XTVERSION reply nor their OSC 1337 support is evidenced yet.
---@type Images.XtversionEntry[]
M.KNOWN = {
  {
    name = "WezTerm",
    match = "wezterm",
    osc1337 = true,
    evidence = "measured: reply `WezTerm 20240203-110809-5046fc22`, images drawn (Windows, 2026-10-31)",
  },
  {
    name = "iTerm2",
    match = "iterm2",
    osc1337 = true,
    evidence = "OSC 1337 is iTerm2's own protocol; reply `iTerm2 3.5.0` (GNOME/vte#235, terminal-query)",
  },
  {
    name = "Konsole",
    match = "konsole",
    osc1337 = true,
    evidence = "already on the environment list (OSC 1337 since Konsole 22.04); "
      .. "reply name NOT evidenced yet (assumed `Konsole <version>`, open follow-up)",
  },
  {
    name = "mintty",
    match = "mintty",
    osc1337 = true,
    evidence = "mintty implements iTerm2 inline images and XTVERSION (GNOME/vte#235)",
  },
  { name = "kitty", match = "kitty", osc1337 = false, evidence = "Kitty graphics protocol only" },
  { name = "Ghostty", match = "ghostty", osc1337 = false, evidence = "Kitty graphics protocol only" },
  { name = "foot", match = "foot", osc1337 = false, evidence = "Sixel only" },
  { name = "XTerm", match = "xterm", osc1337 = false, evidence = "Sixel only" },
}

---@class Images.XtversionAnswer
---@field raw string the reply text after `>|`
---@field name string the reply's name part, as sent
---@field version string|nil the reply's version part
---@field terminal string|nil canonical name from `M.KNOWN`, nil when unlisted
---@field osc1337 boolean|nil `M.KNOWN`'s verdict, nil when unlisted
---@field tmux boolean whether tmux answered instead of the terminal

--- Parse an XTVERSION reply. Pure.
---
--- There is no formal reply format: WezTerm and iTerm2 send `Name version`,
--- kitty, foot and XTerm send `name(version)`. Neovim hands the DCS string to
--- `TermResponse` without its `ESC \` terminator, but a terminated one is
--- accepted too.
---@param seq string|nil the `sequence` field of a `TermResponse` event
---@return Images.XtversionAnswer|nil answer nil when `seq` is not an XTVERSION reply
function M.parse(seq)
  if type(seq) ~= "string" then return nil end
  local text = seq:match("^\27P>|(.*)$")
  if not text then return nil end
  text = vim.trim((text:gsub("\27\\$", ""):gsub("\7$", "")))
  local name, rest = text:match("^([^%s%(]+)(.*)$")
  if not name then return nil end
  local version = vim.trim((rest:gsub("^%s*%(", ""):gsub("%)%s*$", "")))

  ---@type Images.XtversionAnswer
  local answer = { raw = text, name = name, version = version ~= "" and version or nil, tmux = false }
  local lname = name:lower()
  if lname == "tmux" then
    answer.tmux = true
    return answer
  end
  for _, entry in ipairs(M.KNOWN) do
    if lname == entry.match then
      answer.terminal, answer.osc1337 = entry.name, entry.osc1337
      break
    end
  end
  return answer
end

---@alias Images.XtversionState "unsent"|"pending"|"answered"|"silent"|"skipped"

---@type Images.XtversionState
local state = "unsent"
---@type Images.XtversionAnswer|nil
local answer = nil
---@type string|nil
local skipped_why = nil
---@type integer|nil
local autocmd_id = nil
---@type table<string, fun(answer: Images.XtversionAnswer)>
local listeners = {}
--- Bumped by every `M.start` and `M.reset`, so a timeout armed by an earlier
--- probe cannot end a later one.
local generation = 0

---@return nil
local function stop_listening()
  if autocmd_id then
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
    autocmd_id = nil
  end
end

--- Feed one `TermResponse` sequence. Exposed for the spec; the autocmd
--- created by `M.start` calls it for every reply while the probe is pending.
---@param seq string|nil
---@return boolean consumed whether it was the XTVERSION reply
function M.on_response(seq)
  if state ~= "pending" then return false end
  local parsed = M.parse(seq)
  if not parsed then return false end
  answer, state = parsed, "answered"
  stop_listening()
  for _, fn in pairs(listeners) do
    pcall(fn, parsed)
  end
  return true
end

--- Call `fn` once the terminal has answered (or right away, if it already has).
--- Listeners are keyed: registering the same `key` again replaces the earlier
--- listener (repeated `setup()` calls), and `fn = nil` removes it.
---@param key string
---@param fn fun(answer: Images.XtversionAnswer)|nil
---@return nil
function M.on_answer(key, fn)
  listeners[key] = fn
  if fn and answer then pcall(fn, answer) end
end

--- Send the query and listen for the reply. Idempotent while pending or
--- answered; a `silent` or `skipped` probe is sent again (that is what
--- `:Image check` relies on).
---@param env table|nil environment to read (default `vim.env`), for the spec
---@return boolean sent
function M.start(env)
  if state == "pending" or state == "answered" then return false end
  env = env or vim.env

  local why
  if type(vim.api.nvim_ui_send) ~= "function" then
    why = "`nvim_ui_send` is missing"
  elseif #vim.api.nvim_list_uis() == 0 then
    why = "no UI attached"
  elseif type(env.TMUX) == "string" and env.TMUX ~= "" then
    why = "under tmux, which answers for itself"
  end
  if why then
    state, skipped_why = "skipped", why
    return false
  end

  state, skipped_why = "pending", nil
  generation = generation + 1
  local my_generation = generation
  autocmd_id = vim.api.nvim_create_autocmd("TermResponse", {
    group = vim.api.nvim_create_augroup("images.xtversion", { clear = true }),
    callback = function(ev)
      -- Returning true deletes the autocmd; `stop_listening` already did.
      if M.on_response(ev.data and ev.data.sequence) then autocmd_id = nil end
    end,
  })
  vim.defer_fn(function()
    if my_generation == generation and state == "pending" then
      state = "silent"
      stop_listening()
    end
  end, M.TIMEOUT_MS)

  local ok = pcall(vim.api.nvim_ui_send, M.QUERY)
  if not ok then
    state, skipped_why = "skipped", "`nvim_ui_send` failed"
    stop_listening()
    return false
  end
  return true
end

---@class Images.XtversionStatus
---@field state Images.XtversionState
---@field answer Images.XtversionAnswer|nil
---@field why string|nil why the probe was skipped

--- Where the probe stands.
---@return Images.XtversionStatus
function M.status()
  return { state = state, answer = answer, why = skipped_why }
end

--- Forget everything. For tests.
---@return nil
function M.reset()
  stop_listening()
  generation = generation + 1
  state, answer, skipped_why, listeners = "unsent", nil, nil, {}
end

return M
