---@module 'images.paste'
---@brief Save the clipboard image to a file and insert the link.
---@description
--- The everyday case for documentation: take a screenshot, `:Image paste`,
--- done. The image lands as a PNG next to the document (or in the configured
--- subdirectory) and the markdown link is inserted at the cursor.
---
--- With `paste.ask_alt_text = true`, `M.run` asks for alt text before inserting
--- (through ui.nvim's UI kit when present). Default `false`, so the fast case
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

--- ui.nvim's optional UI kit. Without it callers fall back to Neovim's own
--- primitives — the kit is a convenience, not a prerequisite.
---@return table|nil
local function kit()
  local ok, k = pcall(require, "ui.kit")
  return ok and k or nil
end

--- lib.nvim's minimal coroutine async/await runner -- used by
--- `paste_with_name`, a genuinely linear pipeline (capture -> target path ->
--- move -> optional alt text -> insert link). Not used by
--- `images.win_clipboard_worker`, which is a persistent process reacting to
--- several independent, sometimes-racing event sources and stays callback-
--- based for that reason -- see that module's own header.
---@return table
local function async_mod()
  return require("lib.nvim.async")
end

--- Check `out` after a write: does it exist, and is it non-empty? An empty
--- or missing file (nothing was on the clipboard) is reported the same way
--- regardless of which platform branch produced it.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function finish_from_file(out, callback)
  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    callback(false, "no image in the clipboard")
    return
  end
  callback(true)
end

--- Write the clipboard image to `out`. Asynchronous like `images.screenshot`'s
--- `capture`, so both follow the same call contract and
--- `capture_with_optional_name` need not distinguish sync from async.
---@param out string target path (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function clipboard_to_file(out, callback)
  local is_windows = require("lib.nvim.cross.platform.is_windows")()

  -- Windows normally goes through a persistent worker, not a fresh
  -- `powershell.exe` per call -- see images.win_clipboard_worker for why: a
  -- cold `-STA` PowerShell with WinForms/Drawing loaded routinely takes a
  -- second or more (far worse under antivirus/EDR), and a fresh process pays
  -- that on every single paste. `paste.windows_persistent_helper = false`
  -- opts back out of keeping that process alive for the session -- every
  -- paste then falls through to the one-shot command below instead, exactly
  -- as before this module existed. Not unlinking `out` on failure here: the
  -- worker never touches `out` when it reports failure (see its own
  -- protocol -- `$img.Save` only runs on the success path), so there is
  -- nothing of ours to clean up. `out` is always a tempname by the time it
  -- reaches this function -- `M.replace` no longer hands this its final
  -- target directly either (see its own docstring); callers unlink it
  -- themselves on failure, which is the right owner for that decision, not
  -- this function guessing at what `out` means to whoever called it.
  if is_windows and cfg().paste.windows_persistent_helper ~= false then
    require("images.win_clipboard_worker").save_to_file(out, function(ok, err)
      if not ok then
        callback(false, err)
        return
      end
      finish_from_file(out, callback)
    end)
    return
  end

  local cmd ---@type string[]
  -- `wl-paste`/`xclip` write the image to stdout, and this callback writes
  -- those bytes to `out` itself, rather than a shell `>` redirect. `out` is
  -- not always a tempname -- `M.replace` hands it a path resolved from a
  -- Markdown link or the cursor (see `images.resolve.to_path`), which can
  -- legitimately contain a single quote ("John's screenshot.png") or, from a
  -- crafted link, worse. Interpolating that into a `sh -c "... > '%s'"`
  -- string (as this used to) is exactly the shell-injection shape
  -- `images.resolve.to_path`'s own module docs warn about for backtick
  -- command substitution -- an argv array to `wl-paste`/`xclip` plus a
  -- direct file write sidesteps it entirely, no escaping needed.
  local write_stdout = false
  local executable = require("lib.nvim.cross.executable")

  if is_windows then
    -- `paste.windows_persistent_helper = false`: the one-shot command this
    -- module used before the persistent worker existed, unchanged.
    local ps = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;",
      "$img = [System.Windows.Forms.Clipboard]::GetImage();",
      "if ($img -eq $null) { exit 3 };",
      ("$img.Save(%s, [System.Drawing.Imaging.ImageFormat]::Png);"):format(require("images.ps_path").expr(out)),
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
      cmd = { "wl-paste", "--type", "image/png" }
    elseif executable.exists("xclip") then
      cmd = { "xclip", "-selection", "clipboard", "-t", "image/png", "-o" }
    else
      callback(false, "neither `wl-paste` nor `xclip` found")
      return
    end
    write_stdout = true
  end

  -- `text = false` for the stdout-writing branch: `text = true` normalises
  -- `\r\n` to `\n` in the captured output, which would silently corrupt PNG
  -- bytes containing that sequence. The other branch never reads
  -- `result.stdout`, only `result.stderr` for an error message, where the
  -- normalisation is harmless.
  vim.system(cmd, { text = not write_stdout }, function(result)
    vim.schedule(function()
      if result.code == 3 then
        callback(false, "no image in the clipboard")
        return
      end
      if result.code ~= 0 then
        callback(false, ("could not read the clipboard (exit %d): %s"):format(result.code, vim.trim(result.stderr or "")))
        return
      end

      if write_stdout then
        if not result.stdout or #result.stdout == 0 then
          callback(false, "no image in the clipboard")
          return
        end
        local fd = io.open(out, "wb")
        if not fd then
          callback(false, "could not write file: " .. out)
          return
        end
        fd:write(result.stdout)
        fd:close()
      end

      finish_from_file(out, callback)
    end)
  end)
end
-- Exposed for tests: the platform/config branching itself has no UI and no
-- real clipboard in it -- `lib.nvim.cross.platform.is_windows`,
-- `images.win_clipboard_worker` and `vim.system` are stubbed at the seam
-- instead (see TESTS/paste_target_spec.lua).
M.clipboard_to_file = clipboard_to_file

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

--- Words `:Image paste` accepts as a link-path mode, in place of `path=...`.
--- `rel`/`abs` are the short spellings of `relative`/`absolute`.
M.MODE_ALIASES = { rel = "relative", abs = "absolute" }
M.MODE_WORDS = { env = true, repos = true, rel = true, abs = true, relative = true, absolute = true }

---@param p string
---@return string
local function to_fwd(p)
  return (p:gsub("\\", "/"):gsub("/+$", ""))
end

--- `abs` rewritten as `$VAR/rest` for the longest of `roots` that contains it,
--- compared case- and separator-insensitively (Windows paths). nil when none does.
---@param abs string
---@param roots table<string, string|fun(): string|nil> variable name -> directory (or a function returning it)
---@return string|nil
local function shorten_by_roots(abs, roots)
  local fwd = to_fwd(abs)
  -- Case-insensitive only where the file system is (Windows): on Linux/macOS
  -- `/Repos` and `/repos` are different directories.
  local fold = vim.fn.has("win32") == 1 and string.lower or function(s)
    return s
  end
  local lower = fold(fwd)
  local best_var, best_len
  for var, dir in pairs(roots) do
    if type(dir) == "function" then
      local ok, value = pcall(dir)
      dir = ok and value or nil
    end
    if type(dir) == "string" and dir ~= "" then
      local d = fold(to_fwd(dir))
      local inside = lower == d or lower:sub(1, #d + 1) == d .. "/"
      if inside and (not best_len or #d > best_len) then
        best_var, best_len = var, #d
      end
    end
  end
  if not best_var then return nil end
  return "$" .. best_var .. fwd:sub(best_len + 1)
end
M.shorten_by_roots = shorten_by_roots

--- Directories every machine of this setup knows, used when `paste.env_roots`
--- and gopath.nvim do not settle a path: the real values of `$REPOS_DIR` and
--- of Neovim's config directory.
---@return table<string, string|fun(): string|nil>
local function builtin_env_roots()
  return {
    REPOS_DIR = function()
      return vim.env.REPOS_DIR
    end,
    NVIM_CONFIG_DIR = function()
      return vim.fn.stdpath("config")
    end,
  }
end

--- `abs` spelled with an environment variable, or nil when it lies under no
--- known root. Order: the user's own `paste.env_roots` (most explicit), then
--- gopath.nvim's `shorten_path` -- the logic behind `:Gopath to-repos-dir` /
--- `to-nvim-dir`, which also recognises a repos root by folder name across
--- machines -- then the built-in roots above for a setup without gopath.
---@param abs string
---@return string|nil
function M.env_link_path(abs)
  local custom = shorten_by_roots(abs, cfg().paste.env_roots or {})
  if custom then return custom end

  local ok, gopath = pcall(require, "gopath.env_shorten")
  if ok and type(gopath.shorten_path) == "function" then
    local shortened = gopath.shorten_path(abs)
    if shortened then return shortened end
  end

  return shorten_by_roots(abs, builtin_env_roots())
end

--- Turn the doc-relative link path `doc_rel` into whatever `mode` asks for.
--- Only the STRING inserted into the markdown link changes here — the file
--- itself always lands next to the document (or in `paste.dir`/an existing
--- resource folder, see `target_paths`), exactly as before this existed;
--- `mode` only picks how that location is spelled out in the link text.
---@param abs string absolute path of the image file on disk
---@param doc_rel string path relative to the document's own directory — what "relative" (the only behaviour before this existed) produces
---@param mode string|nil "relative" (default/nil) | "absolute" | "repos" | "env" | a literal custom prefix; "rel"/"abs" are accepted spellings of the first two
---@return string|nil link_path
---@return string|nil err
local function resolve_link_path(abs, doc_rel, mode)
  mode = M.MODE_ALIASES[mode or ""] or mode
  if not mode or mode == "" or mode == "relative" then return doc_rel, nil end

  if mode == "env" then
    -- Rooted at an environment variable when the file sits under a known
    -- root, else the doc-relative path: the same "outside the root" fallback
    -- as "repos" below, and never an error -- a document outside every known
    -- root is an ordinary case, not a misconfiguration.
    return M.env_link_path(abs) or doc_rel, nil
  end

  local forward_abs = (abs:gsub("\\", "/"))
  if mode == "absolute" then return forward_abs, nil end

  if mode == "repos" then
    local repos_dir = vim.env.REPOS_DIR
    if not repos_dir or repos_dir == "" then return nil, "$REPOS_DIR is not set" end
    local norm_repos = (repos_dir:gsub("\\", "/"))
    if forward_abs:sub(1, #norm_repos + 1) == norm_repos .. "/" then return forward_abs:sub(#norm_repos + 2), nil end
    -- Outside $REPOS_DIR: fall back to the same doc-relative path "relative"
    -- would produce, rather than erroring — mirrors buffer-ctx.nvim's
    -- ops/filepath.lua (mode="repos"), which falls back to the cwd-relative
    -- path for this same "outside the root" case, reserving the hard error
    -- for the variable being unset outright.
    return doc_rel, nil
  end

  -- Anything else is a literal custom prefix, joined onto the doc-relative
  -- path — e.g. mode="/static/img" -> "/static/img/assets/shot-1.png".
  return (mode:gsub("/+$", "")) .. "/" .. doc_rel, nil
end
-- Exposed for tests: a pure function, no filesystem or terminal needed.
M.resolve_link_path = resolve_link_path

--- Determine the target path for a new image and create the directory. Runs
--- only AFTER a successful capture (see `paste_with_name`) — otherwise an empty
--- clipboard, for instance, would still create an `assets` directory with
--- nothing written into it.
---@param buf integer
---@param filename_override string|nil an already sanitised name; nil = template
---@param path_mode string|nil see `resolve_link_path`; nil = "relative"
---@return string|nil absolute path
---@return string|nil link path to use in the markdown link
---@return string|nil err
local function target_paths(buf, filename_override, path_mode)
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
  local doc_rel = (sub ~= "") and (sub .. "/" .. file) or file

  local link_path, mode_err = resolve_link_path(abs, doc_rel, path_mode)
  if not link_path then return nil, nil, mode_err end
  return abs, link_path, nil
end

--- Move `src` to `dst`. `fs_rename` fails across drive boundaries (EXDEV, the
--- normal case on Windows between the temp and project drives) — then it
--- stages a copy of `src` next to `dst` (same directory, so guaranteed the
--- same volume) and `fs_rename`s *that* into place, rather than
--- `fs_copyfile`ing straight over `dst`.
---
--- That staging step is what makes this atomic even across the EXDEV case:
--- `fs_copyfile` overwrites its target in place, non-atomically — anything
--- that interrupts it mid-copy (Neovim killed, disk full, an AV/EDR lock)
--- leaves a truncated or mixed-bytes `dst` behind. Copying into a same-
--- volume staging file first confines that exact risk to the staging file,
--- which is disposable; `dst` itself is only ever touched by the final
--- `fs_rename`, which is atomic by definition (POSIX `rename(2)`; Windows'
--- `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING`, which is what `fs_rename`
--- uses under `dst` already existing). `M.replace` is the caller this
--- matters for — `dst` there is a real, pre-existing file worth protecting,
--- not a fresh tempname.
---@param src string
---@param dst string
---@return boolean ok
local function move_file(src, dst)
  if vim.uv.fs_rename(src, dst) then return true end

  local dir = vim.fn.fnamemodify(dst, ":h")
  local staging = ("%s/.%s.%d.tmp"):format(dir, vim.fn.fnamemodify(dst, ":t"), vim.uv.hrtime())
  if vim.uv.fs_copyfile(src, staging) then
    if vim.uv.fs_rename(staging, dst) then
      pcall(vim.uv.fs_unlink, src)
      return true
    end
    pcall(vim.uv.fs_unlink, staging)
  end
  return false
end
-- Exposed for tests: `vim.uv.fs_rename` is stubbed to force the EXDEV
-- fallback (no real second drive needed) -- see TESTS/paste_target_spec.lua.
M.move_file = move_file

--- Put the cursor where the link still needs typing -- its empty alt text, or
--- the path of one that already has alt text -- and enter insert mode, instead
--- of leaving it behind the link where nothing is left to write
--- (`lib.nvim.markdown.link_cursor`, tuned by `paste.link_cursor`). Falls back
--- to the old behaviour (cursor behind the link) without that module.
---@param win integer
---@param buf integer the buffer the link went into
---@param row integer 0-based row the link was inserted at
---@param col integer 0-based byte column the link starts at
---@param link string the inserted text
---@return nil
local function place_cursor(win, buf, row, col, link)
  -- The paste is asynchronous: if the window has since switched to another
  -- buffer, `row`/`col` mean nothing there, so the cursor is left alone.
  if vim.api.nvim_win_get_buf(win) ~= buf then return end
  local ok, link_cursor = pcall(require, "lib.nvim.markdown.link_cursor")
  if ok and link_cursor.place(win, row, col, link, cfg().paste.link_cursor, buf) then return end
  pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col + #link })
end

--- Insert the link at the cursor position valid at the time of the call. Runs
--- after the clipboard write — synchronously right afterwards, or
--- asynchronously after the alt-text prompt — and therefore rechecks the
--- buffer's and window's state: between determining them and reaching here
--- there was at least one synchronous process call, plus user input in the
--- alt-text case. The buffer may have been closed or set `nomodifiable` in the
--- meantime, and the window that was current when the paste started may no
--- longer be — `k.input`'s alt-text prompt runs its `on_submit` from the
--- input float's own context, so `vim.api.nvim_win_get_cursor(0)` there would
--- return the popup's cursor, not the document's. `win` is therefore captured
--- by the caller before any of that can happen (see `paste_with_name`), not
--- read here. Either way the image is written regardless — only the link is
--- missing, and the user should hear about it.
---@param buf integer
---@param win integer window current when the paste started
---@param rel string path as it goes into the link (relative, absolute, or env-rooted -- see `resolve_link_path`)
---@param alt string|nil alt text; empty or nil = no alt text
---@return nil
local function insert_link(buf, win, rel, alt)
  if not vim.api.nvim_buf_is_valid(buf) then
    notify().warn("the buffer is gone — the image is at " .. rel)
    return
  end
  if not vim.bo[buf].modifiable then
    notify().warn("the buffer is not modifiable — the image is at " .. rel)
    return
  end
  if not vim.api.nvim_win_is_valid(win) then
    notify().warn("the window is gone — the image is at " .. rel)
    return
  end
  -- The insertion point is read from `win`'s cursor; a window that has since
  -- switched to another buffer holds a position that means nothing in `buf`.
  if vim.api.nvim_win_get_buf(win) ~= buf then
    notify().warn("the window no longer shows the document — the image is at " .. rel)
    return
  end

  -- Avoid backslashes in the link: markdown paths travel better with `/`.
  local forward = (rel:gsub("\\", "/"))
  local c = cfg().paste
  local link = (alt and alt ~= "") and c.alt_link_template:format(alt, forward) or c.link_template:format(forward)

  local pos = vim.api.nvim_win_get_cursor(win)
  local inserted = pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { link })
  if not inserted then
    notify().warn("could not insert the link — the image is at " .. rel)
    return
  end
  place_cursor(win, buf, pos[1] - 1, pos[2], link)

  notify().info("image saved: " .. rel)
end

--- Await the alt-text prompt: ui.kit's `input` when available -- its
--- `on_submit`/`on_cancel` fire from the input float's own context, the
--- main loop, same as every other kit-backed callback in this file --
--- otherwise the already-synchronous `vim.fn.input` fallback, which needs
--- no await at all.
---@return string|nil alt empty/nil = no alt text (also nil on cancel)
local function await_alt_text()
  local k = kit()
  if k and k.input then
    return async_mod().await(function(resume)
      k.input({
        title = "Alt text (empty = none)",
        on_submit = function(alt)
          resume(alt)
        end,
        -- Cancelling should still insert the link, just without alt text — by
        -- this point the image is already on disk, and a lost link (kit.input
        -- calls nothing at all on <Esc> without on_cancel) would be the worse
        -- surprise than a link without alt text.
        on_cancel = function()
          resume(nil)
        end,
      })
    end)
  end
  return vim.fn.input("Alt text (empty = none): ")
end

--- The second half of `M.run`/`M.screenshot`, after an optional name prompt:
--- produce the image file via `capture(out, cb)` and then optionally ask for
--- alt text. `capture` is interchangeable — `clipboard_to_file` for `:Image
--- paste`, `images.screenshot.capture` for `:Image screenshot` — and everything
--- after it (target path, link, alt text) is identical for both.
---
--- Written against `lib.nvim.async`, not nested callbacks: this is a
--- genuinely linear pipeline (capture -> target path -> move -> optional alt
--- text -> insert link) -- unlike `images.win_clipboard_worker`, which reacts
--- to several independent, sometimes-racing event sources (a stdout stream,
--- a cancellable timeout, process exit) and stays callback-based for exactly
--- that reason (see that module's own header). `async.wrap`/`async.await`
--- add no scheduling of their own on top of `capture`'s/`k.input`'s own
--- callbacks -- they only suspend and resume the coroutine, so every
--- `vim.fn`/`vim.api` call below still only ever runs from a context those
--- callbacks already guarantee is main-loop-safe, the same assumption the
--- pre-async version of this function depended on.
---
--- `capture` writes to a temporary file first, not straight into `paste.dir` —
--- only after a successful capture is the target directory determined
--- (including `find_existing_resource_dir`), created if needed, and the file
--- moved there. If `capture` aborts (no image in the clipboard, a screenshot
--- cancelled with <Esc>), no empty `paste.dir` is left behind either.
---@param buf integer
---@param filename_override string|nil already sanitised; nil = template
---@param capture fun(out: string, cb: fun(ok: boolean, err: string|nil))
---@param path_mode string|nil see `resolve_link_path`; nil = "relative"
---@return nil
local function paste_with_name(buf, filename_override, capture, path_mode)
  if vim.api.nvim_buf_get_name(buf) == "" then
    notify().error("the buffer has no file name — save it first")
    return
  end

  -- Captured now, alongside `buf` -- the one point before the async gap
  -- `capture` opens where both are certainly still valid (see
  -- `insert_link`'s docstring for why `win` in particular has to be).
  local win = vim.api.nvim_get_current_win()
  local tmp = vim.fn.tempname() .. ".png"
  local async = async_mod()
  local await_capture = async.wrap(capture, 2)

  async.run(function()
    local ok, cap_err = await_capture(tmp)
    if not ok then
      pcall(vim.uv.fs_unlink, tmp)
      notify().warn(cap_err or "paste failed")
      return
    end

    local abs, rel, err = target_paths(buf, filename_override, path_mode)
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

    local alt = nil
    if cfg().paste.ask_alt_text then alt = await_alt_text() end
    insert_link(buf, win, rel, alt)
  end, nil, { tag = "images.paste" })
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
---@param path_mode string|nil see `resolve_link_path`; nil = "relative"
---@return nil
local function capture_with_optional_name(capture, direct_name, force_ask, path_mode)
  local buf = vim.api.nvim_get_current_buf()

  if direct_name then
    local sanitized = sanitize_filename(direct_name)
    if not sanitized then
      notify().error("invalid file name: " .. direct_name)
      return
    end
    paste_with_name(buf, sanitized, capture, path_mode)
    return
  end

  -- `force_ask` is how a keymap asks for a name. With `ask_filename` on, the
  -- prompt already happens and this changes nothing; with it off, a bare
  -- keypress previously had no way to name the file at all -- only
  -- `:Image paste {name}` did.
  if not (cfg().paste.ask_filename or force_ask) then
    paste_with_name(buf, nil, capture, path_mode)
    return
  end

  local suggested = default_filename(buf)
  local k = kit()
  if k and k.input then
    k.input({
      title = "File name",
      default = suggested,
      on_submit = function(name)
        paste_with_name(buf, sanitize_filename(name), capture, path_mode)
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
    paste_with_name(buf, sanitize_filename(name), capture, path_mode)
  end
end

--- Choose the path mode for the link (see `resolve_link_path`): an explicit
--- `path=...` argument (`:Image paste path=absolute`) wins outright; without
--- one, a configured `paste.default_path_mode` is used silently — default
--- `"relative"`, the only behaviour before this existed, so a plain
--- `:Image paste`/keymap paste stays a one-keypress, no-prompt action.
--- Setting that option to `false` means "ask me every time", and only then
--- does the interactive choice (ui.nvim's UI kit, falling back to
--- `vim.ui.select`/`vim.fn.input`) appear.
---@param explicit_mode string|nil already given via `path=...`
---@param on_resolved fun(mode: string|nil) mode = nil means "cancelled"
---@return nil
local function resolve_path_mode(explicit_mode, on_resolved)
  if explicit_mode and explicit_mode ~= "" then
    on_resolved(explicit_mode)
    return
  end

  local default_mode = cfg().paste.default_path_mode
  if default_mode and default_mode ~= "" then
    on_resolved(default_mode)
    return
  end

  local choices = {
    { label = "relative to the document", value = "relative" },
    { label = "absolute filesystem path", value = "absolute" },
    { label = "$REPOS_DIR-rooted", value = "repos" },
    { label = "environment-variable-rooted ($NVIM_CONFIG_DIR, $REPOS_DIR, …)", value = "env" },
    { label = "custom prefix…", value = "custom" },
  }

  local function ask_custom_prefix()
    local k = kit()
    if k and k.input then
      k.input({
        title = "Custom path prefix",
        on_submit = function(prefix)
          on_resolved((prefix and prefix ~= "") and prefix or nil)
        end,
        on_cancel = function()
          on_resolved(nil)
        end,
      })
    else
      local prefix = vim.fn.input("Custom path prefix: ")
      on_resolved(prefix ~= "" and prefix or nil)
    end
  end

  local function handle_choice(choice)
    if not choice then
      on_resolved(nil)
      return
    end
    if choice.value == "custom" then
      ask_custom_prefix()
    else
      on_resolved(choice.value)
    end
  end

  local k = kit()
  if k and k.select then
    k.select({
      items = choices,
      title = "Image link path",
      format_item = function(c)
        return c.label
      end,
      on_select = handle_choice,
      on_cancel = function()
        on_resolved(nil)
      end,
    })
  else
    vim.ui.select(choices, {
      prompt = "Image link path",
      format_item = function(c)
        return c.label
      end,
    }, handle_choice)
  end
end
-- Exposed for tests: drives the interactive choice with a faked kit()/vim.ui.select.
M.resolve_path_mode = resolve_path_mode

--- Save the clipboard image and insert the link at the cursor.
---@param name string|nil a file name already given (`:Image paste {name}`) — skips any name prompt
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@param path_mode string|nil already given via `path=...` (see `resolve_path_mode`); nil = `paste.default_path_mode`, asked interactively when that is `false`
---@return nil
function M.run(name, force_ask, path_mode)
  resolve_path_mode(path_mode, function(mode)
    if not mode then
      notify().info("cancelled")
      return
    end
    capture_with_optional_name(clipboard_to_file, name, force_ask, mode)
  end)
end

-- Exposed for tests: both take `capture` as a parameter, so a fake suffices --
-- no real clipboard and no real interactive screenshot needed.
M.paste_with_name = paste_with_name
M.capture_with_optional_name = capture_with_optional_name

--- Capture an interactive screen selection straight into a file and process it
--- like `M.run` — the everyday case in one step instead of three (launch a
--- screenshot tool by hand, clipboard, `:Image paste`).
---
--- Path mode is deliberately pinned to "relative" here, not threaded through
--- `resolve_path_mode`: `:Image screenshot` has no `path=...` argument (only
--- `:Image paste` does, see `usrcmds.lua`), so it must stay exactly the
--- one-keypress action it always was, unaffected by `paste.default_path_mode`.
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@return nil
function M.screenshot(force_ask)
  local screenshot = require("images.screenshot")
  if not screenshot.available() then
    notify().error(screenshot.unavailable_reason())
    return
  end
  capture_with_optional_name(screenshot.capture, nil, force_ask, "relative")
end

--- Replace an existing image with the clipboard contents, without touching the
--- link. Useful for updating a stale screenshot in place rather than creating a
--- new file and link.
---
--- Writes to a tempname first and only `move_file`s it over `file` once the
--- read fully succeeded — the same pattern `paste_with_name` already uses for
--- a fresh paste, applied here too. `clipboard_to_file` used to be handed
--- `file` directly: on Windows, the persistent worker's `$img.Save(file, ...)`
--- writes straight into it, non-atomically, so a read killed mid-write (the
--- clipboard timeout, or the process dying) could leave `file` truncated —
--- and unlike a failed *paste* (nothing lost, `out` was never anything real),
--- a failed *replace* would corrupt the very image it was supposed to
--- update. Routing through a tempname means the worst case on any failure is
--- an orphaned tempname; `file` itself is only ever touched by `move_file`'s
--- atomic rename, after `ok` is already known to be `true`.
---@param path string|nil nil = the image under the cursor
---@return nil
function M.replace(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return
  end

  -- Read before the write, not after: `move_file`'s `fs_rename` replaces
  -- `file`'s directory entry with the tempname's inode outright (same for
  -- its `fs_copyfile`+`fs_rename` fallback -- the staging file is a fresh
  -- one too), so the resulting file has the *new* file's permissions, not
  -- `file`'s -- e.g. a deliberate `chmod 600` would silently become
  -- whatever the OS temp directory's default is. `fs_chmod` afterwards
  -- restores the bits explicitly; harmless no-op-ish on Windows, where
  -- `vim.uv.fs_chmod` has no POSIX mode bits to restore.
  local prior = vim.uv.fs_stat(file)

  local tmp = vim.fn.tempname() .. ".png"
  clipboard_to_file(tmp, function(ok, err)
    if not ok then
      pcall(vim.uv.fs_unlink, tmp)
      notify().warn(err or "replacement failed")
      return
    end
    if not move_file(tmp, file) then
      pcall(vim.uv.fs_unlink, tmp)
      notify().error("could not replace the file: " .. file)
      return
    end
    if prior then pcall(vim.uv.fs_chmod, file, prior.mode) end
    notify().info("replaced: " .. vim.fn.fnamemodify(file, ":~"))
  end)
end

return M
