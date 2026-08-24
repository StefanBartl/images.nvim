---@module 'images.screenshot'
---@brief Capture an interactive screen selection straight into a file.
---@description
--- Replaces three everyday steps (launch a screenshot tool by hand ->
--- clipboard -> `:Image paste`) with one: `:Image screenshot` starts the
--- selection and then continues exactly like `:Image paste` (see
--- `images.paste`'s `capture_with_optional_name`).
---
--- Asynchronous throughout (`vim.system` without `:wait()`, every
--- continuation inside `vim.schedule`), never a blocking `sleep`: a selection
--- takes the user anywhere from seconds to a minute, and `:wait()` blocks
--- Neovim's entire event loop for the subprocess's lifetime — a frozen editor
--- while all you are doing is dragging a rectangle. The same construction as
--- `lib.nvim.system.job`, which avoids `:wait()` for precisely this reason.
---
--- Platforms, in decreasing order of reliability:
---
--- * macOS — `screencapture -i`: interactive selection by dragging or clicking
---   a window, writing straight to the target file. If the user cancels with
---   <Esc>, `screencapture` still exits 0 — a cancellation is not visible in
---   the exit code, only in the missing/empty file.
---
--- * Linux — `grim -g "$(slurp)"` (Wayland, both tools needed) or `maim -s`
---   (X11, one tool suffices). `slurp` writes the region the user dragged to
---   stdout; if they cancel it writes nothing and `grim` is never invoked.
---
--- * Windows — the least certain of the three. There is no documented CLI
---   invocation that makes the modern Snipping Tool write directly to a file.
---   `explorer.exe ms-screenclip:` launches the selection UI (the same as
---   Win+Shift+S) but returns immediately and copies the result to the
---   clipboard when finished — with no signal for when that happens. This
---   module then polls the clipboard on a timer (non-blocking) for a *new*
---   image, with a timeout. The polling/comparison logic itself was verified
---   manually against a clipboard changed on an artificial delay; whether
---   `ms-screenclip:` launches as documented on every Windows version could
---   not be simulated in this environment — `:Image paste` remains the
---   unchanged, proven two-step route should this automation ever fail.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Check the file after a capture: does it exist, and is it non-empty? The
--- shared ending for macOS/Linux, where a cancellation (<Esc>) is not visible
--- in the exit code, only in the missing/empty file.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function finish_from_file(out, callback)
  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    callback(false, "cancelled")
    return
  end
  callback(true)
end

-- ── macOS ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_mac(out, callback)
  vim.system({ "screencapture", "-i", out }, { text = true }, function()
    vim.schedule(function()
      finish_from_file(out, callback)
    end)
  end)
end

-- ── Linux ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_linux(out, callback)
  local executable = require("lib.nvim.cross.executable")
  if executable.exists("grim") and executable.exists("slurp") then
    vim.system({ "slurp" }, { text = true }, function(sel)
      vim.schedule(function()
        if sel.code ~= 0 or vim.trim(sel.stdout or "") == "" then
          callback(false, "cancelled")
          return
        end
        vim.system({ "grim", "-g", vim.trim(sel.stdout), out }, { text = true }, function(gr)
          vim.schedule(function()
            if gr.code ~= 0 then
              callback(false, "grim failed: " .. vim.trim(gr.stderr or ""))
              return
            end
            finish_from_file(out, callback)
          end)
        end)
      end)
    end)
  elseif executable.exists("maim") then
    -- -s: interactive drag selection. Cancelling (<Esc>) exits non-zero.
    vim.system({ "maim", "-s", out }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(false, "cancelled")
          return
        end
        finish_from_file(out, callback)
      end)
    end)
  else
    callback(false, "neither `grim`+`slurp` (Wayland) nor `maim` (X11) found")
  end
end

-- ── Windows ──────────────────────────────────────────────────────────────────

--- PowerShell fragment: print the current clipboard image as base64, or
--- nothing when there is none. Reused for the baseline snapshot and for every
--- poll tick.
local PS_READ_CLIPBOARD_B64 = table.concat({
  "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;",
  "$img = [System.Windows.Forms.Clipboard]::GetImage();",
  "if ($img -eq $null) { exit 0 };",
  "$ms = New-Object System.IO.MemoryStream;",
  "$img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png);",
  "[Convert]::ToBase64String($ms.ToArray());",
}, " ")

--- Read the current clipboard image content, asynchronously.
---@param callback fun(data: string|nil)
---@return nil
local function read_clipboard_image_async(callback)
  vim.system(
    { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", PS_READ_CLIPBOARD_B64 },
    { text = true },
    function(result)
      vim.schedule(function()
        local out = vim.trim(result.stdout or "")
        if result.code ~= 0 or out == "" then
          callback(nil)
          return
        end
        local ok, decoded = pcall(vim.base64.decode, out)
        callback((ok and decoded ~= "") and decoded or nil)
      end)
    end
  )
end

--- Launch the snip UI, wait on a timer (non-blocking) for a *new* clipboard
--- image, then write it to `out`.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_windows(out, callback)
  read_clipboard_image_async(function(baseline)
    vim.system({ "explorer.exe", "ms-screenclip:" }, { text = true }, function(launch)
      vim.schedule(function()
        if launch.code ~= 0 then
          callback(false, "could not launch the Snipping Tool")
          return
        end

        local c = cfg().display.screenshot
        local timeout_ms = c.windows_timeout_ms or 60000
        local interval_ms = c.windows_poll_interval_ms or 600
        local elapsed = 0

        local timer = assert(vim.uv.new_timer())
        local function stop()
          if not timer:is_closing() then
            timer:stop()
            timer:close()
          end
        end

        timer:start(
          interval_ms,
          interval_ms,
          vim.schedule_wrap(function()
            elapsed = elapsed + interval_ms
            read_clipboard_image_async(function(current)
              if current and current ~= baseline then
                stop()
                local fd = io.open(out, "wb")
                if not fd then
                  callback(false, "target file not writable: " .. out)
                  return
                end
                fd:write(current)
                fd:close()
                callback(true)
              elseif elapsed >= timeout_ms then
                stop()
                callback(false, "timed out — no new capture detected in the clipboard")
              end
            end)
          end)
        )
      end)
    end)
  end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Whether this platform offers any capture route at all.
---@return boolean
function M.available()
  local executable = require("lib.nvim.cross.executable")
  if require("lib.nvim.cross.platform.is_macos")() then
    return executable.exists("screencapture")
  elseif require("lib.nvim.cross.platform.is_windows")() then
    return true -- ms-screenclip: ships with Windows, no separate tool needed
  else
    return (executable.exists("grim") and executable.exists("slurp")) or executable.exists("maim")
  end
end

--- The reason `available()` is false — for the error message.
---@return string
function M.unavailable_reason()
  if require("lib.nvim.cross.platform.is_macos")() then return "`screencapture` not found (normally ships with macOS)" end
  return "neither `grim`+`slurp` (Wayland) nor `maim` (X11) found"
end

--- Start an interactive screen selection and write it to `out`. Returns
--- immediately; `callback(ok, err)` runs once the user is done, has cancelled,
--- or (Windows only) the timeout was reached.
---@param out string target path (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
function M.capture(out, callback)
  if require("lib.nvim.cross.platform.is_macos")() then
    capture_mac(out, callback)
  elseif require("lib.nvim.cross.platform.is_windows")() then
    capture_windows(out, callback)
  else
    capture_linux(out, callback)
  end
end

return M
