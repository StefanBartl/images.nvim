---@module 'images.paste'
---@brief Save the clipboard image to a file and insert the link.
---@description
--- The everyday case for documentation: take a screenshot, `:Image paste`,
--- done. The image lands as a PNG next to the document (or in the configured
--- subdirectory) and the markdown link is inserted at the cursor.
---
--- With `paste.ask_alt_text = true`, `M.run` asks for alt text before inserting
--- (through lib.nvim's UI kit when present). Default `false`, so the fast case
--- — screenshot, one keypress, done — is not interrupted by a prompt most
--- invocations do not need.
---
--- Platforms:
--- * Windows — `powershell.exe -STA` with `System.Windows.Forms.Clipboard`.
---   The `-STA` is mandatory: the clipboard API requires a single-threaded
---   apartment thread, otherwise it always returns `null`. Deliberately
---   `powershell.exe` (5.1) rather than `pwsh`, because PowerShell 7 has no
---   `-STA` and WinForms is not reliably available there.
--- * Linux — `wl-paste` (Wayland), otherwise `xclip` (X11).
--- * macOS — `pngpaste`, if installed.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- lib.nvim's optional UI kit. Without it callers fall back to Neovim's own
--- primitives — the kit is a convenience, not a prerequisite.
---@return table|nil
local function kit()
  local ok, k = pcall(require, "lib.nvim.ui.kit")
  return ok and k or nil
end

--- Write the clipboard image to `out`. Asynchronous like `images.screenshot`'s
--- `capture`, so both follow the same call contract and
--- `capture_with_optional_name` need not distinguish sync from async — the read
--- itself is a single fast process call (milliseconds), not a multi-second
--- interactive procedure like a screen selection; a `:wait()` would be harmless
--- here, but a uniform signature is still cleaner than a special rule for this
--- one case.
---@param out string target path (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function clipboard_to_file(out, callback)
  local cmd ---@type string[]
  local executable = require("lib.nvim.cross.executable")

  if require("lib.nvim.cross.platform.is_windows")() then
    local ps = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;",
      "$img = [System.Windows.Forms.Clipboard]::GetImage();",
      "if ($img -eq $null) { exit 3 };",
      ("$img.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png);"):format(out:gsub("'", "''")),
    }, " ")
    cmd = { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", ps }
  elseif require("lib.nvim.cross.platform.is_macos")() then
    if not executable.exists("pngpaste") then
      callback(false, "`pngpaste` not found (brew install pngpaste)")
      return
    end
    cmd = { "pngpaste", out }
  else
    if executable.exists("wl-paste") then
      cmd = { "sh", "-c", ("wl-paste --type image/png > '%s'"):format(out) }
    elseif executable.exists("xclip") then
      cmd = { "sh", "-c", ("xclip -selection clipboard -t image/png -o > '%s'"):format(out) }
    else
      callback(false, "neither `wl-paste` nor `xclip` found")
      return
    end
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 3 then
        callback(false, "no image in the clipboard")
        return
      end
      if result.code ~= 0 then
        callback(false, ("could not read the clipboard (exit %d): %s"):format(result.code, vim.trim(result.stderr or "")))
        return
      end

      local stat = vim.uv.fs_stat(out)
      if not stat or stat.size == 0 then
        pcall(vim.uv.fs_unlink, out)
        callback(false, "no image in the clipboard")
        return
      end
      callback(true)
    end)
  end)
end

--- The suggested file name from the template — the prefill for the name prompt
--- and the fallback when no input of the user's own arrives.
---@param buf integer
---@return string|nil suggestion nil when the buffer has no file name
local function default_filename(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  local doc_stem = vim.fn.fnamemodify(name, ":t:r")
  return cfg().paste.name_template:format(doc_stem, os.time())
end

--- Turn user input into a safe file name.
---
--- Only the file name itself counts: any path component entered (directories,
--- `..`) is discarded via `:t` rather than honoured — otherwise input like
--- `../../x` could write outside `paste.dir`. The extension is always forced to
--- `.png`, because `clipboard_to_file` writes PNG bytes regardless of the name;
--- any other extension would merely be mislabelled.
---@param input string raw user input
---@return string|nil the cleaned file name with `.png`, or nil when nothing usable remains
local function sanitize_filename(input)
  -- `fnamemodify(":t")` treats `\` as a path separator on Windows only -- on
  -- Linux/macOS a backslash is a valid file name character, so an entered
  -- "C:\Windows\name" would survive intact there. Normalising to `/` manually
  -- first makes the split platform-independent.
  local normalized = vim.trim(input or ""):gsub("\\", "/")
  local base = vim.fn.fnamemodify(normalized, ":t")
  local stem = vim.trim(vim.fn.fnamemodify(base, ":r"))
  if stem == "" or stem == "." or stem == ".." then return nil end
  return stem .. ".png"
end
-- Exposed for tests: a pure function, no terminal or filesystem needed.
M.sanitize_filename = sanitize_filename

--- Find an existing resource directory in the document's directory (e.g.
--- "Resources"/"Ressourcen", see `paste.existing_dir_names`) — when one exists
--- it is used instead of `paste.dir`, so that a second storage folder
--- ("assets") does not appear alongside one already being maintained.
--- Case-insensitive matching: Windows filesystems are case-insensitive anyway,
--- and an exact `"resources"` would otherwise miss an existing `Resources`.
---@param doc_dir string
---@return string|nil name of the directory found, as it appears on disk
local function find_existing_resource_dir(doc_dir)
  local candidates = cfg().paste.existing_dir_names
  if not candidates or #candidates == 0 then return nil end

  local wanted = {}
  for _, n in ipairs(candidates) do
    wanted[n:lower()] = true
  end

  local entries = vim.fn.readdir(doc_dir) or {}
  for _, entry in ipairs(entries) do
    if wanted[entry:lower()] and vim.fn.isdirectory(doc_dir .. "/" .. entry) == 1 then return entry end
  end
  return nil
end
-- Exposed for tests: reads only, never writes.
M.find_existing_resource_dir = find_existing_resource_dir

--- Determine the target path for a new image and create the directory. Runs
--- only AFTER a successful capture (see `paste_with_name`) — otherwise an empty
--- clipboard, for instance, would still create an `assets` directory with
--- nothing written into it.
---@param buf integer
---@param filename_override string|nil an already sanitised name; nil = template
---@return string|nil absolute path
---@return string|nil relative path for the link
---@return string|nil err
local function target_paths(buf, filename_override)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil, nil, "the buffer has no file name — save it first" end

  local c = cfg().paste
  local doc_dir = vim.fn.fnamemodify(name, ":p:h")
  local doc_stem = vim.fn.fnamemodify(name, ":t:r")

  local sub = find_existing_resource_dir(doc_dir) or c.dir or ""
  local dir = (sub ~= "") and (doc_dir .. "/" .. sub) or doc_dir
  if vim.fn.isdirectory(dir) == 0 then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok then return nil, nil, "could not create the directory: " .. dir end
  end

  local file = filename_override or c.name_template:format(doc_stem, os.time())
  local abs = dir .. "/" .. file
  local rel = (sub ~= "") and (sub .. "/" .. file) or file
  return abs, rel, nil
end

--- Move `src` to `dst`. `fs_rename` fails across drive boundaries (EXDEV, the
--- normal case on Windows between the temp and project drives) — then it copies
--- instead and deletes the original.
---@param src string
---@param dst string
---@return boolean ok
local function move_file(src, dst)
  if vim.uv.fs_rename(src, dst) then return true end
  if vim.uv.fs_copyfile(src, dst) then
    pcall(vim.uv.fs_unlink, src)
    return true
  end
  return false
end

--- Insert the link at the cursor position valid at the time of the call. Runs
--- after the clipboard write — synchronously right afterwards, or
--- asynchronously after the alt-text prompt — and therefore rechecks the
--- buffer's state: between determining the buffer and reaching here there was
--- at least one synchronous process call, plus user input in the alt-text case.
--- The buffer may have been closed or set `nomodifiable` in the meantime — the
--- image is written either way, only the link is missing, and the user should
--- hear about it.
---@param buf integer
---@param rel string path relative to the document
---@param alt string|nil alt text; empty or nil = no alt text
---@return nil
local function insert_link(buf, rel, alt)
  if not vim.api.nvim_buf_is_valid(buf) then
    notify().warn("the buffer is gone — the image is at " .. rel)
    return
  end
  if not vim.bo[buf].modifiable then
    notify().warn("the buffer is not modifiable — the image is at " .. rel)
    return
  end

  -- Avoid backslashes in the link: markdown paths travel better with `/`.
  local forward = (rel:gsub("\\", "/"))
  local c = cfg().paste
  local link = (alt and alt ~= "") and c.alt_link_template:format(alt, forward) or c.link_template:format(forward)

  local pos = vim.api.nvim_win_get_cursor(0)
  local inserted = pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { link })
  if not inserted then
    notify().warn("could not insert the link — the image is at " .. rel)
    return
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { pos[1], pos[2] + #link })

  notify().info("image saved: " .. rel)
end

--- The second half of `M.run`/`M.screenshot`, after an optional name prompt:
--- produce the image file via `capture(out, cb)` and then optionally ask for
--- alt text. `capture` is interchangeable — `clipboard_to_file` for `:Image
--- paste`, `images.screenshot.capture` for `:Image screenshot` — and everything
--- after it (target path, link, alt text) is identical for both. Asynchronous,
--- because an interactive screen selection can take anywhere from seconds to a
--- minute, and blocking on that would freeze Neovim for the duration.
---
--- `capture` writes to a temporary file first, not straight into `paste.dir` —
--- only after a successful capture is the target directory determined
--- (including `find_existing_resource_dir`), created if needed, and the file
--- moved there. If `capture` aborts (no image in the clipboard, a screenshot
--- cancelled with <Esc>), no empty `paste.dir` is left behind either.
---@param buf integer
---@param filename_override string|nil already sanitised; nil = template
---@param capture fun(out: string, cb: fun(ok: boolean, err: string|nil))
---@return nil
local function paste_with_name(buf, filename_override, capture)
  if vim.api.nvim_buf_get_name(buf) == "" then
    notify().error("the buffer has no file name — save it first")
    return
  end

  local tmp = vim.fn.tempname() .. ".png"

  capture(tmp, function(ok, cap_err)
    if not ok then
      pcall(vim.uv.fs_unlink, tmp)
      notify().warn(cap_err or "paste failed")
      return
    end

    local abs, rel, err = target_paths(buf, filename_override)
    if not abs or not rel then
      pcall(vim.uv.fs_unlink, tmp)
      notify().error(err or "cannot determine the target path")
      return
    end

    if not move_file(tmp, abs) then
      pcall(vim.uv.fs_unlink, tmp)
      notify().error("could not move the file: " .. abs)
      return
    end

    if not cfg().paste.ask_alt_text then
      insert_link(buf, rel, nil)
      return
    end

    local k = kit()
    if k and k.input then
      k.input({
        title = "Alt text (empty = none)",
        on_submit = function(alt)
          insert_link(buf, rel, alt)
        end,
        -- Cancelling should still insert the link, just without alt text — by
        -- this point the image is already on disk, and a lost link (kit.input
        -- calls nothing at all on <Esc> without on_cancel) would be the worse
        -- surprise than a link without alt text.
        on_cancel = function()
          insert_link(buf, rel, nil)
        end,
      })
    else
      local alt = vim.fn.input("Alt text (empty = none): ")
      insert_link(buf, rel, alt)
    end
  end)
end

--- Optionally ask for a file name, then run `paste_with_name` with `capture` as
--- the capture function. The shared core of `M.run` (clipboard) and
--- `M.screenshot` (interactive screen selection) — the two differ only in HOW
--- the image file comes into being.
---
--- `direct_name` comes from `:Image paste {name}` — when set it is used
--- (sanitised) directly and neither the interactive prompt nor
--- `paste.ask_filename` applies: the name was already given at the call site,
--- so there is nothing left to ask.
---@param capture fun(out: string, cb: fun(ok: boolean, err: string|nil))
---@param direct_name string|nil a name already given as a command argument
---@param force_ask boolean|nil  # prompt even when `paste.ask_filename` is off
---@return nil
local function capture_with_optional_name(capture, direct_name, force_ask)
  local buf = vim.api.nvim_get_current_buf()

  if direct_name then
    local sanitized = sanitize_filename(direct_name)
    if not sanitized then
      notify().error("invalid file name: " .. direct_name)
      return
    end
    paste_with_name(buf, sanitized, capture)
    return
  end

  -- `force_ask` is how a keymap asks for a name. With `ask_filename` on, the
  -- prompt already happens and this changes nothing; with it off, a bare
  -- keypress previously had no way to name the file at all -- only
  -- `:Image paste {name}` did.
  if not (cfg().paste.ask_filename or force_ask) then
    paste_with_name(buf, nil, capture)
    return
  end

  local suggested = default_filename(buf)
  local k = kit()
  if k and k.input then
    k.input({
      title = "File name",
      default = suggested,
      on_submit = function(name)
        paste_with_name(buf, sanitize_filename(name), capture)
      end,
      -- Unlike the alt-text prompt: nothing has been captured or written yet, so
      -- cancelling really does mean "do nothing" rather than "carry on with
      -- defaults".
      on_cancel = function()
        notify().info("cancelled")
      end,
    })
  else
    local name = vim.fn.input("File name: ", suggested or "")
    if name == "" then
      notify().info("cancelled")
      return
    end
    paste_with_name(buf, sanitize_filename(name), capture)
  end
end

--- Save the clipboard image and insert the link at the cursor.
---@param name string|nil a file name already given (`:Image paste {name}`) — skips any name prompt
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@return nil
function M.run(name, force_ask)
  capture_with_optional_name(clipboard_to_file, name, force_ask)
end

-- Exposed for tests: both take `capture` as a parameter, so a fake suffices --
-- no real clipboard and no real interactive screenshot needed.
M.paste_with_name = paste_with_name
M.capture_with_optional_name = capture_with_optional_name

--- Capture an interactive screen selection straight into a file and process it
--- like `M.run` — the everyday case in one step instead of three (launch a
--- screenshot tool by hand, clipboard, `:Image paste`).
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@return nil
function M.screenshot(force_ask)
  local screenshot = require("images.screenshot")
  if not screenshot.available() then
    notify().error(screenshot.unavailable_reason())
    return
  end
  capture_with_optional_name(screenshot.capture, nil, force_ask)
end

--- Replace an existing image with the clipboard contents, without touching the
--- link. Useful for updating a stale screenshot in place rather than creating a
--- new file and link.
---@param path string|nil nil = the image under the cursor
---@return nil
function M.replace(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return
  end

  clipboard_to_file(file, function(ok, err)
    if not ok then
      notify().warn(err or "replacement failed")
      return
    end
    notify().info("replaced: " .. vim.fn.fnamemodify(file, ":~"))
  end)
end

return M
