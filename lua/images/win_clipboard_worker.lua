---@module 'images.win_clipboard_worker'
---@brief A persistent PowerShell `-STA` helper for reading the Windows clipboard.
---@description
--- `:Image paste` on Windows needs a `-STA` PowerShell process with
--- `System.Windows.Forms`/`System.Drawing` loaded (see `images.paste`'s
--- `clipboard_to_file`). Loading those assemblies is the expensive part of
--- that process -- roughly a second on a warm machine, measured here; far
--- more under antivirus/EDR real-time scanning of the PowerShell host and
--- its assemblies, the same risk `images.screenshot` already documents for
--- its own polling reads. A fresh `powershell.exe -STA` pays that cost again
--- on *every* paste.
---
--- This module keeps ONE such process alive for the whole Neovim session --
--- started lazily on the first paste, reused after that -- so only the first
--- paste pays the cold-start cost; every one after it is a single line over
--- stdin and a matching line back over stdout, on the order of
--- milliseconds (measured: ~15ms against ~1s cold, on the machine this was
--- built on).
---
--- Protocol: one line in, one line out. `powershell.exe -Command -` reads
--- and executes each stdin line as it arrives (verified empirically -- this
--- is not documented PowerShell behaviour) rather than buffering until EOF,
--- which is what makes a request/response pair over a single long-lived
--- process possible at all. Each request line ends with a
--- `IMAGESNVIM:<code>:<message>` marker written to stdout; requests are
--- queued and sent one at a time, since a single stdout stream gives no
--- other way to tell one response from another.
---
--- A request that never answers (a hung PowerShell -- the same AV/EDR risk
--- mentioned above) is bounded by `paste.windows_clipboard_timeout_ms`: on
--- timeout the process is killed, every queued request fails, and the next
--- call starts a fresh process. Better an occasional slow paste than a
--- silently wedged one for the rest of the session.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@class Images.ClipboardWorker.Request
---@field out string target path (PNG)
---@field callback fun(ok: boolean, err: string|nil)

---@class Images.ClipboardWorker
---@field proc table|nil the `vim.system` handle (has `:write`, `:kill`); nil only until `ensure_worker` finishes spawning it
---@field buffer string undelivered stdout, up to the last incomplete line
---@field queue Images.ClipboardWorker.Request[] requests waiting to be sent
---@field in_flight Images.ClipboardWorker.Request|nil the one request sent but not yet answered
---@field timer table|nil the in-flight request's timeout timer, if any

---@type Images.ClipboardWorker|nil
local worker = nil

local RESPONSE_PATTERN = "^IMAGESNVIM:(%d):(.*)$"

--- Stop `w`'s timeout timer, if one is running.
---@param w Images.ClipboardWorker
---@return nil
local function stop_timer(w)
  if w.timer and not w.timer:is_closing() then
    w.timer:stop()
    w.timer:close()
  end
  w.timer = nil
end

--- Fail every request `w` is holding (the in-flight one and everything still
--- queued) with `err`, and drop the worker so the next call starts a fresh
--- process. Used for both a hard failure (the process died) and a timeout
--- (the process may still be alive but is not answering, so it is killed
--- first -- see `send_next`), and by `M.shutdown` on `VimLeavePre`.
---
--- Each callback runs through `pcall`: a caller's callback is arbitrary code
--- (`images.paste`'s, ultimately) this module does not control, and one
--- throwing must not stop the rest of `pending` from being notified, or --
--- for the `shutdown` caller specifically -- prevent it from reaching its own
--- `w.proc:write(nil)` right after this returns.
---@param w Images.ClipboardWorker
---@param err string
---@return nil
local function fail_all(w, err)
  if worker == w then worker = nil end
  stop_timer(w)
  if w.in_flight then
    pcall(w.in_flight.callback, false, err)
    w.in_flight = nil
  end
  local pending = w.queue
  w.queue = {}
  for _, req in ipairs(pending) do
    pcall(req.callback, false, err)
  end
end

--- Send the next queued request, if the worker is idle and one is waiting.
--- No-op when a request is already in flight -- `handle_response` calls this
--- again once that one is answered.
---@param w Images.ClipboardWorker
---@return nil
local function send_next(w)
  if w.in_flight or #w.queue == 0 then return end
  local req = table.remove(w.queue, 1)
  w.in_flight = req

  local timeout_ms = cfg().paste.windows_clipboard_timeout_ms
  if type(timeout_ms) ~= "number" or timeout_ms ~= timeout_ms or timeout_ms < 1 then timeout_ms = 20000 end

  local timer = assert(vim.uv.new_timer())
  w.timer = timer
  timer:start(
    math.floor(timeout_ms),
    0,
    vim.schedule_wrap(function()
      -- Stale fire (already answered, or a later fail_all already tore this
      -- worker down): the timer was stopped/closed then, this is a leftover
      -- tick that raced it.
      if worker ~= w or w.in_flight ~= req then return end
      pcall(function()
        w.proc:kill("sigkill")
      end)
      fail_all(w, "clipboard read timed out")
    end)
  )

  -- `req.out` is a tempname `paste.lua` itself creates, never user input --
  -- still escaped the same way the previous one-shot command did, on
  -- general principle (a single quote in a temp directory name is not
  -- impossible, e.g. a OneDrive-synced profile path).
  local escaped = req.out:gsub("'", "''")
  local line = (
    "try { Add-Type -AssemblyName System.Windows.Forms,System.Drawing -ErrorAction Stop;"
    .. " $img = [System.Windows.Forms.Clipboard]::GetImage();"
    .. " if ($img -eq $null) { Write-Output 'IMAGESNVIM:3:' }"
    .. " else { $img.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png); Write-Output 'IMAGESNVIM:0:' } }"
    .. " catch { Write-Output ('IMAGESNVIM:1:' + ($_.Exception.Message -replace \"`r`n|`n\", ' ')) }"
  ):format(escaped)

  local write_ok = pcall(function()
    w.proc:write(line .. "\n")
  end)
  if not write_ok then fail_all(w, "could not talk to the clipboard helper") end
end

--- Resolve the in-flight request with a parsed response line, then move on
--- to whatever is queued next.
---
--- Each `callback` invocation runs through `pcall`, same reasoning as
--- `fail_all`: this is the ordinary response path, taken on every normal
--- paste, far more often than `fail_all` runs -- a throwing callback here
--- must not stop `send_next(w)` below from running, or whatever is queued
--- behind this request would never be sent at all (nothing else re-enters
--- `send_next` until the next unrelated `save_to_file` call happens to).
---@param w Images.ClipboardWorker
---@param code string "0" ok | "3" no image | anything else = error
---@param message string only meaningful for the error case
---@return nil
local function handle_response(w, code, message)
  stop_timer(w)
  local req = w.in_flight
  w.in_flight = nil
  if not req then return end -- a stray line with no request waiting on it

  if code == "3" then
    pcall(req.callback, false, "no image in the clipboard")
  elseif code == "0" then
    pcall(req.callback, true)
  else
    local trimmed = vim.trim(message or "")
    pcall(req.callback, false, trimmed ~= "" and trimmed or "could not read the clipboard")
  end
  send_next(w)
end

--- The worker's stdout callback: buffer arriving text, pull out every
--- complete line, and act on the ones that match the response marker.
--- Anything else (blank lines, PowerShell's own line-editing echo) is
--- ignored rather than treated as a protocol error -- silence here would be
--- far worse than an ignored stray line.
---@param w Images.ClipboardWorker
---@param err string|nil
---@param data string|nil nil = stream closed
---@return nil
local function on_stdout(w, err, data)
  if err or not data then return end
  w.buffer = w.buffer .. data
  while true do
    local nl = w.buffer:find("\n", 1, true)
    if not nl then break end
    local line = w.buffer:sub(1, nl - 1):gsub("\r$", "")
    w.buffer = w.buffer:sub(nl + 1)
    local code, message = line:match(RESPONSE_PATTERN)
    if code then vim.schedule(function()
      if worker == w then handle_response(w, code, message) end
    end) end
  end
end

--- Get the live worker, spawning one if none is running.
---@return Images.ClipboardWorker|nil nil = the process could not be started
local function ensure_worker()
  if worker then return worker end

  ---@type Images.ClipboardWorker
  local w = { buffer = "", queue = {}, in_flight = nil, timer = nil, proc = nil }

  local spawn_ok, proc = pcall(
    vim.system,
    { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", "-" },
    {
      stdin = true,
      text = true,
      stdout = function(err, data)
        on_stdout(w, err, data)
      end,
      stderr = function() end,
    },
    vim.schedule_wrap(function()
      if worker == w then fail_all(w, "the clipboard helper stopped unexpectedly") end
    end)
  )
  if not spawn_ok or not proc then return nil end

  w.proc = proc
  worker = w
  return w
end

--- Save the current clipboard image to `out` (PNG). Queues behind any
--- request already in flight on the shared worker; starts the worker first
--- if this is the first call in the session.
---@param out string target path
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
function M.save_to_file(out, callback)
  local w = ensure_worker()
  if not w then
    callback(false, "could not start the clipboard helper")
    return
  end
  table.insert(w.queue, { out = out, callback = callback })
  send_next(w)
end

--- Close the worker's stdin, letting the PowerShell process exit on its
--- own (verified: it exits cleanly on stdin EOF, no forced kill needed).
--- Called from `images.bindings.autocmds`' `VimLeavePre`; a no-op when no
--- worker has ever been started, or on any other platform.
---
--- Goes through `fail_all` rather than dropping `worker` directly: a request
--- can legitimately still be in flight (or queued behind one) when Neovim
--- quits, and its callback is what unlinks a stray temp file / shows a
--- warning in `images.paste` -- skipping it would leave that caller waiting
--- on a callback that never comes, on the one path this module's own
--- "every held request gets answered" contract did not actually cover.
---@return nil
function M.shutdown()
  local w = worker
  if not w then return end
  fail_all(w, "shutting down")
  pcall(function()
    w.proc:write(nil)
  end)
end

-- Exposed for tests: lets a spec force a fresh worker between cases instead
-- of leaking state across them (there is no other way to reach module-local
-- `worker` from outside).
---@return nil
function M._reset()
  worker = nil
end

return M
