---@module 'images'
---@brief Entry point for images.nvim — `:Image` and the public Lua API.
---@description
--- Show images in the terminal without Neovim leaving the terminal.
---
--- The difference to snacks.image and image.nvim: both speak the Kitty graphics
--- protocol exclusively. On native Windows Neovim in WezTerm that is never
--- drawn when it comes from Neovim — this plugin uses the iTerm2 protocol (OSC
--- 1337) instead, which works reliably there.
---
--- Every display function returns a `boolean` and reports errors through
--- `lib.nvim.notify`. The low-level modules (`terminal`, `gallery`, `info`)
--- never notify themselves but return `ok, err` — the decision whether an error
--- reaches the user is made here.
---@see images.terminal for the protocol details and the pitfalls
---@see images.gallery for laying several images out on a grid
---@see images.paste for the clipboard workflow

local M = {}

--- The most recently displayed target, for `:Image next`/`prev`.
---@type { buf: integer, index: integer }|nil
local cursor_state = nil

--- Whether the current image is pinned (no automatic clearing).
---@type boolean
local pinned = false

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- lib.nvim's optional UI kit. Without it callers fall back to Neovim's own
--- primitives — the kit is a convenience, not a prerequisite.
---@return table|nil
local function kit()
  local ok, k = pcall(require, "lib.nvim.ui.kit")
  return ok and k or nil
end

--- Register the autocmds that remove a displayed image again. Nothing happens
--- for pinned images (`M.pin`). Closes an open hover float
--- (`display.hover_mode = "float"`), otherwise the standard overlay — `M.pin`'s
--- un-pin path knows only this one augroup name and therefore need not know
--- which mode is currently active.
---@return nil
local function arm_clear()
  if pinned then return end
  local events = cfg().display.clear_events
  if not events or #events == 0 then return end
  require("lib.nvim.bindings.autocmd").create(events, function()
    if require("images.hover_float").is_open() then
      require("images.hover_float").close()
    elseif require("images.ascii").is_open() then
      require("images.ascii").close()
    else
      require("images.terminal").clear()
    end
  end, {
    group = require("lib.nvim.bindings.autocmd").group("images.clear", true),
    once = true,
  })
end

--- Guard before the first draw: can this terminal show images at all? Shared
--- with `images.browse`/`images.zen`, which face the same draw path — see
--- `images.guard` for the reasoning.
---@return nil
local function guard_capability()
  require("images.guard").check()
end

--- Pick a start row such that a block of height `rows` still fits on screen.
--- Without the cap a tall image slides below the bottom edge.
---@param rows integer
---@return integer
local function row_below_cursor(rows)
  local screen_row = vim.fn.screenrow()
  return math.max(1, math.min(screen_row + 1, vim.o.lines - rows - 1))
end

-- ── Display ──────────────────────────────────────────────────────────────────

--- Display an image file.
---
--- For an http(s) URL this is asynchronous: the download runs in the background
--- (it used to block until the configured timeout, default 10s) and the display
--- happens in its callback. `true` then means "download started", errors arrive
--- via notify — the same split `M.export` already has.
---@param path string absolute or relative path, or an http(s) URL
---@return boolean ok
function M.show(path)
  ---@param file string
  ---@return boolean ok
  local function display_file(file)
    local display = cfg().display
    local cap = require("images.terminal").capability(display.assume_supported)

    -- The terminal probably cannot do OSC 1337: rather than the warning plus an
    -- ineffective draw attempt, use the block-graphics alternative when
    -- ImageMagick is available and the fallback is not switched off.
    if not cap.ok then
      local ascii_cfg = display.ascii_fallback or {}
      local ascii = require("images.ascii")
      if ascii_cfg.enabled ~= false and ascii.available() then
        local ok, err = ascii.open(file, display)
        if not ok then
          notify().error(err or "the ASCII fallback failed")
          return false
        end
        arm_clear()
        return true
      end
    end

    guard_capability()

    if display.hover_mode == "float" then
      if not require("images.hover_float").open(file) then return false end
    else
      local ok, err =
        require("images.terminal").draw(file, row_below_cursor(display.max_rows), 1, display.max_cols, display.max_rows)
      if not ok then
        notify().error(err or "could not display the image")
        return false
      end
    end

    arm_clear()
    return true
  end

  if require("images.remote").is_remote(path) then
    require("images.remote").fetch(path, function(fetched, remote_err)
      if not fetched then
        notify().error(remote_err or "could not download the remote image")
        return
      end
      display_file(fetched)
    end)
    return true
  end

  local file = require("images.resolve").to_path(path)
  if not file then
    notify().error("image not found: " .. tostring(path))
    return false
  end

  return display_file(file)
end

--- Display the image under the cursor (a markdown link or a file name).
---@return boolean ok
function M.hover()
  local target, err = require("images.resolve").under_cursor()
  if not target then
    notify().warn(err or "no image under the cursor")
    return false
  end
  return M.show(target.path)
end

--- Display several images side by side.
---@param paths string[]|nil absolute paths; nil = every image in the buffer
---@param columns integer|nil column count; nil = automatic
---@return boolean ok
function M.gallery(paths, columns)
  if not paths then
    local found = require("images.scan").buffer(0)
    paths = {}
    for _, t in ipairs(found) do
      paths[#paths + 1] = t.path
    end
  end

  if #paths == 0 then
    notify().info("no images to display")
    return false
  end

  guard_capability()

  local display = cfg().display
  -- The gallery may take up more area than a single display: it is the explicit
  -- overview mode, not the passing glance.
  local height = math.max(6, math.floor(vim.o.lines * 0.7))
  local placements, skipped = require("images.gallery").layout(paths, {
    columns = columns,
    gap = display.gallery_gap,
    top = math.max(1, math.floor((vim.o.lines - height) / 2)),
    left = 1,
    width = vim.o.columns - 2,
    height = height,
  })

  if #placements == 0 then
    notify().warn("not enough room for a gallery — enlarge the window or use fewer images")
    return false
  end

  local drawn, errors = require("images.terminal").draw_many(placements)
  if drawn == 0 then
    notify().error(errors[1] or "could not draw the gallery")
    return false
  end

  if skipped > 0 or #errors > 0 then notify().warn(("%d of %d images not shown"):format(skipped + #errors, #paths)) end

  arm_clear()
  return true
end

--- Display the images of a line range side by side. A thin wrapper around
--- `M.gallery` that resolves the range into targets — for `:'<,'>Image gallery`
--- and the ranged case of bare `:Image` (see `bindings/usrcmds.lua`).
---@param first integer 1-based first line
---@param last integer 1-based last line
---@param columns integer|nil column count; nil = automatic
---@return boolean ok
function M.gallery_range(first, last, columns)
  local found = require("images.scan").buffer(0, first, last)
  local paths = {}
  for _, t in ipairs(found) do
    paths[#paths + 1] = t.path
  end
  if #paths == 0 then
    notify().info("no images in this range")
    return false
  end
  return M.gallery(paths, columns)
end

--- List the buffer's images and pick one to display. Uses lib.nvim's UI kit
--- when present, otherwise `vim.ui.select`.
---@param first integer|nil 1-based first line (for `:'<,'>Image list`)
---@param last integer|nil 1-based last line
---@return nil
function M.list(first, last)
  local found, missing = require("images.scan").buffer(0, first, last)

  if #missing > 0 then notify().warn(("%d image link(s) unresolvable, e.g. %s"):format(#missing, missing[1])) end
  if #found == 0 then
    notify().info("no images in this buffer")
    return
  end
  if #found == 1 then
    M.show(found[1].path)
    return
  end

  ---@param item ImagesNvim.Target
  local function format_item(item)
    return ("%4d  %s"):format(item.lnum, item.raw)
  end

  local k = kit()
  if k and k.select then
    k.select({
      items = found,
      title = "Images in this buffer",
      format_item = format_item,
      on_select = function(choice)
        if choice then M.show(choice.path) end
      end,
    })
    return
  end

  vim.ui.select(found, { prompt = "Show image", format_item = format_item }, function(choice)
    if choice then M.show(choice.path) end
  end)
end

--- Jump to the buffer's next/previous image and display it.
---@param delta integer 1 = forwards, -1 = backwards
---@return boolean ok
function M.step(delta)
  local buf = vim.api.nvim_get_current_buf()
  local found = require("images.scan").buffer(buf)
  if #found == 0 then
    notify().info("no images in this buffer")
    return false
  end

  local index
  if cursor_state and cursor_state.buf == buf then
    index = cursor_state.index + delta
  else
    -- First call in this buffer: start at the image nearest the cursor rather
    -- than bluntly at 1 — otherwise you jump unexpectedly to the beginning from
    -- the middle of a long document.
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    index = 1
    for i, t in ipairs(found) do
      if t.lnum <= lnum then index = i end
    end
    if delta > 0 and found[index] and found[index].lnum <= lnum then index = index + delta end
  end

  -- Wrap around rather than bumping into the ends.
  index = ((index - 1) % #found) + 1
  cursor_state = { buf = buf, index = index }

  local target = found[index]
  -- The scan ran over the buffer contents; an edit in the meantime may have put
  -- the line outside the valid range.
  local line_count = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(target.lnum, line_count), 0 })
  return M.show(target.path)
end

-- ── Metadata, clipboard, clearing ────────────────────────────────────────────

--- Display an image's metadata.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.info(path)
  local file
  if path then
    file = require("images.resolve").to_path(path)
  else
    local target = require("images.resolve").under_cursor()
    file = target and target.path
  end
  if not file then
    notify().warn("no image found")
    return false
  end

  local data, err = require("images.info").collect(file)
  if not data then
    notify().error(err or "metadata not readable")
    return false
  end

  local lines = require("images.info").lines(data)
  local k = kit()
  if k and k.viewer then
    k.viewer({ title = "Image info", message = lines })
  else
    notify().info(table.concat(lines, "\n"))
  end
  return true
end

--- Save the clipboard image and link it.
---@param name string|nil a file name already given — skips any name prompt
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@return nil
function M.paste(name, force_ask)
  require("images.paste").run(name, force_ask)
end

--- Capture a screen selection interactively, save it and link it — the same
--- route as `M.paste`, only that the image file comes from a screen selection
--- rather than the clipboard. Returns immediately; the result arrives
--- asynchronously, see `images.screenshot`.
---@param force_ask boolean|nil  # prompt for a name even when `ask_filename` is off
---@return nil
function M.screenshot(force_ask)
  require("images.paste").screenshot(force_ask)
end

--- Replace an existing image with the clipboard contents, without touching the
--- link.
---@param path string|nil nil = the image under the cursor
---@return nil
function M.replace(path)
  require("images.paste").replace(path)
end

--- Export an image as a PDF next to the source file — the opposite direction of
--- pdfport.s "PDF page as an image" (still open there). Runs through pdfport.nvim (losslessly via img2pdf) when
--- installed and available; otherwise through `magick` — both paths
--- asynchronous, see `images.convert.to_pdf`.
---@param path string|nil nil = the image under the cursor
---@return boolean ok  true = the export was started (the result arrives
---asynchronously via notify on both paths); false = never started at all (no
---image found)
function M.export(path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  require("images.convert").to_pdf(file, function(ok, out_path_or_err)
    if ok then
      notify().info("exported: " .. vim.fn.fnamemodify(out_path_or_err, ":~"))
    else
      notify().error(out_path_or_err or "export failed")
    end
  end)

  return true
end

--- Write a resized copy of an image next to the source
--- ("photo.png" -> "photo.scaled.png"); the original stays untouched.
---
--- The command is `:Image scale` and this function is `M.scale`, while the
--- module underneath is `images.convert.resize` — the difference is
--- deliberate, see that module's docs: `images.scale` is a different file
--- entirely (display arithmetic) and prose about it has to keep meaning one
--- thing.
---@param spec string geometry: "50%", "800x600", "800x", "x600", "800x600!" or "800"
---@param path string|nil nil = the image under the cursor
---@return boolean ok  true = the resize was started (the result arrives
---asynchronously); false = never started at all (no image found)
function M.scale(spec, path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  require("images.convert").resize(file, spec, function(out_path, err)
    if not out_path then
      notify().error(err or "resize failed")
      return
    end
    notify().info("scaled: " .. vim.fn.fnamemodify(out_path, ":~"))
  end)

  return true
end

--- Write a smaller copy of an image next to the source
--- ("photo.png" -> "photo.optimised.png"); the original stays untouched.
---
--- Reports the size change in both directions, including the case where there
--- was none — a copy that did not get smaller is deleted rather than left
--- lying next to the original, see `images.convert.optimise`.
---@param path string|nil nil = the image under the cursor
---@param opts { quality?: integer }|nil  quality 1-100 for lossy formats; omitted = keep the source's
---@return boolean ok  true = the optimisation was started; false = no image found
function M.optimise(path, opts)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  local human = require("images.info").human_size

  require("images.convert").optimise(file, opts, function(out_path, err, before, after)
    if err then
      notify().error(err)
      return
    end
    if not out_path then
      -- Not an error: the file was already as small as this can make it. Said
      -- plainly, with the numbers, because "nothing happened" without them
      -- reads like a failure.
      notify().info(
        ("%s is already optimal (%s, best attempt %s) — nothing written"):format(
          vim.fn.fnamemodify(file, ":t"),
          human(before or 0),
          human(after or 0)
        )
      )
      return
    end
    local saved = (before or 0) - (after or 0)
    notify().info(
      ("optimised: %s (%s -> %s, %s smaller)"):format(
        vim.fn.fnamemodify(out_path, ":~"),
        human(before or 0),
        human(after or 0),
        human(saved)
      )
    )
  end)

  return true
end

--- Write a copy of an image in another format, on the same stem
--- ("photo.jpg" -> "photo.png"); the original stays untouched.
---
--- `pdf` as a target runs through the same route as `M.export`, pdfport.nvim
--- included — see `images.convert.to_format`.
---@param format string target extension without the dot, see `images.convert.target_formats`
---@param path string|nil nil = the image under the cursor
---@return boolean ok  true = the conversion was started; false = no image found
function M.convert(format, path)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  require("images.convert").to_format(file, format, function(out_path, err)
    if not out_path then
      notify().error(err or "conversion failed")
      return
    end
    notify().info("converted: " .. vim.fn.fnamemodify(out_path, ":~"))
  end)

  return true
end

--- Read the text out of an image — or out of the one under the cursor — and
--- open it in a scratch split.
---
--- A split, not `kit.viewer` (which `M.info` uses) and not a `make_scratch`
--- float (which `M.zen` uses): both of those are for *looking at* something.
--- Recognised text is raw material — you correct a misread character, select a
--- paragraph and hit `:Translate`, yank a stack trace, `:w` it next to the
--- case. A read-only popup that closes on `q` is wrong for every one of those.
---
--- The buffer is named after the source image and reused, so running this
--- twice on the same screenshot replaces the previous result instead of
--- stacking a second window; two different images get two buffers.
--- `filetype=markdown` is what makes `language.nvim`'s spell checking and
--- `:Translate` treat the contents as prose without any further wiring.
---@param path string|nil nil = the image under the cursor
---@param opts { lang?: string, args?: string[] }|nil  nil = the configured language (`ocr.lang`)
---@return boolean ok  true = OCR was started (the result arrives asynchronously);
---false = never started at all (no image found)
function M.ocr(path, opts)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  local ocr = require("images.ocr")
  ocr.run(file, opts, function(text, err)
    if not text then
      notify().error(err or "OCR failed")
      return
    end

    local name = vim.fn.fnamemodify(file, ":t")
    require("lib.nvim.window.open_named_scratch")("images://ocr/" .. name, ocr.to_lines(text), {
      filetype = "markdown",
      split = "below",
      modifiable = true,
    })
  end)

  return true
end

--- Open an image — or the one under the cursor — in redaction mode: mark boxes
--- (visual mode + `<CR>`), black them out with `w` and save as a new file; the
--- original stays unchanged.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.redact(path)
  return require("images.redact").open(path)
end

--- Find image files in the target directory that no link points to any more,
--- and offer to delete one. Deletes only after explicit confirmation —
--- *finding* orphaned images should be risk-free, even if `:Image orphans` is
--- run twice by accident.
---@return nil
function M.orphans()
  local orphans = require("images.orphans").find()
  if #orphans == 0 then
    notify().info("no orphaned images found")
    return
  end

  ---@param o Images.Orphan
  local function format_item(o)
    return o.rel
  end

  ---@param choice Images.Orphan|nil
  local function on_pick(choice)
    if not choice then return end

    ---@param confirmed boolean
    local function delete_if_confirmed(confirmed)
      if not confirmed then return end
      local ok = pcall(vim.uv.fs_unlink, choice.path)
      if ok then
        notify().info("deleted: " .. choice.rel)
      else
        notify().error("could not delete: " .. choice.rel)
      end
    end

    local k = kit()
    if k and k.confirm then
      -- Explicit `choices`: without them `on_answer` yields a boolean rather
      -- than the label (see kit.confirm's M.confirm — `custom` switches between
      -- the two), and being explicit keeps both paths' wording identical.
      k.confirm({
        question = ("Delete '%s'?"):format(choice.rel),
        choices = { "Yes", "No" },
        on_answer = function(answer)
          delete_if_confirmed(answer == "Yes")
        end,
      })
    else
      delete_if_confirmed(vim.fn.confirm(("Delete '%s'?"):format(choice.rel), "&Yes\n&No", 2) == 1)
    end
  end

  local k = kit()
  local title = ("%d orphaned image(s)"):format(#orphans)
  if k and k.select then
    k.select({ items = orphans, title = title, format_item = format_item, on_select = on_pick })
  else
    vim.ui.select(orphans, { prompt = title, format_item = format_item }, on_pick)
  end
end

--- Browse images below a scope and pick one, with a live preview when
--- snacks.picker is installed.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil for scope="path": the target directory
---@return nil
function M.browse(scope, arg)
  require("images.browse").open(scope, arg)
end

--- Show the image under the cursor (or at `path`) in a large, editable window —
--- it survives a hover popup (from snacks, say) opening alongside it, see
--- `images.zen`.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.zen(path)
  return require("images.zen").open(path)
end

--- Reliably draw an image — or the one under the cursor — in a window (or the
--- window showing a buffer) at a named position. Unlike `M.show` (always the
--- current window, below the cursor) or `M.zen`/`M.hover_float` (fixed windows
--- with a lifecycle of their own), this function fixes the position itself —
--- for callers that want to know exactly where the image lands, e.g. other
--- plugins that already have a window open.
---
--- No remote images (the same boundary as `M.zen`/`M.export`/`M.redact` — only
--- `M.show`/hover download URLs, see `display.remote`'s docs in
--- `images.config.DEFAULTS`).
---@param target integer|nil window or buffer handle; nil/0 = current window
---@param position string see `images.scale.POSITIONS` ("full", "center", "top-left", …)
---@param path string|nil nil = the image under the cursor
---@param opts Images.Anchor.Opts|nil
---@return boolean ok for `opts.defer = true`: whether the call was accepted, not whether anything was drawn yet
---@return string|nil err
function M.draw(target, position, path, opts)
  local file = require("images.resolve").path_or_cursor(path)
  if not file then
    notify().warn("no image under the cursor or at the given path")
    return false, "no image found"
  end

  guard_capability()

  opts = opts or {}
  local user_on_done = opts.on_done
  local merged_opts = vim.tbl_extend("force", opts, {
    -- `images.anchor.draw` calls this exactly once in every case — synchronously
    -- when `target` cannot be resolved or `defer` is unset, otherwise as soon as
    -- the deferred attempt has settled. A failure therefore reaches the user
    -- either way, not only on the immediate path.
    on_done = function(ok, err)
      if not ok then notify().error(err or "could not display the image") end
      if user_on_done then user_on_done(ok, err) end
    end,
  })

  return require("images.anchor").draw(target, position, file, merged_opts)
end

--- Pick two images below a scope and compare them side by side.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil for scope="path": the target directory
---@return nil
function M.compare(scope, arg)
  require("images.compare").open(scope, arg)
end

--- A short status line indicator: empty when no image is displayed. For
--- lualine: `{ require("images").statusline }`.
---@param opts { icon?: string, pinned_suffix?: string }|nil
---@return string
function M.statusline(opts)
  opts = opts or {}
  if not require("images.terminal").is_showing() then return "" end
  local icon = opts.icon or "🖼"
  if pinned then return icon .. (opts.pinned_suffix or "📌") end
  return icon
end

--- Turn automatic clearing for the current image on or off.
---@param on boolean|nil nil = toggle
---@return boolean pinned the new state
function M.pin(on)
  if on == nil then
    pinned = not pinned
  else
    pinned = on and true or false
  end

  if pinned then
    -- Withdraw any clearing autocmds already armed, or the next cursor movement
    -- would clear the image that was just pinned.
    pcall(vim.api.nvim_del_augroup_by_name, "images.clear")
    notify().info("image pinned — `:Image clear` removes it")
  else
    notify().info("the image will be removed on the next cursor movement")
    arm_clear()
  end
  return pinned
end

--- Remove the displayed images, including an open zen window or hover float.
---@return nil
function M.clear()
  pinned = false
  cursor_state = nil
  require("images.zen").close()
  require("images.hover_float").close()
  require("images.ascii").close()
  require("images.terminal").clear()
end

--- Run the capability check again. Needed when `assume_supported` was set after
--- the fact — otherwise the memoized result stands.
---@return Images.Capability
function M.recheck()
  require("images.guard").reset()
  require("images.terminal").reset_capability()
  local cap = require("images.terminal").capability(require("images.config").get().display.assume_supported)
  if cap.ok then
    notify().info("image output available" .. (cap.terminal and (" (" .. cap.terminal .. ")") or ""))
  else
    notify().warn(table.concat({ cap.reason or "", cap.hint or "" }, "\n"))
  end
  return cap
end

--- Set the plugin up.
---@param opts ImagesNvim.Opts|nil see `images.config.DEFAULTS`
---@return nil
function M.setup(opts)
  local conf = require("images.config").setup(opts)
  require("images.bindings.usrcmds").register(conf)
  require("images.bindings.keymaps").register(conf)
  require("images.bindings.autocmds").register(conf)

  -- Adopt `display.cell_aspect`, so the draw box sits tightly around the image
  -- rather than around the 0.5 assumption. Configured, not measured — why
  -- measuring is impossible from inside Neovim is explained in images.cell.
  require("images.cell").apply()

  -- A one-off popup (persisted across restarts) on the first `setup()` after
  -- installation: which CLI tools unlock what, and why (docs/install.json).
  -- `:Lib deps show images.nvim` repeats it at any time afterwards.
  -- `conf.deps_popup = false` (right in the setup() spec, config/DEFAULTS.lua)
  -- disables it for this plugin. pcall'd: an older lib.nvim without
  -- lib.nvim.deps must not break setup() over a purely informational popup.
  if conf.deps_popup ~= false then
    local ok_deps, deps = pcall(require, "lib.nvim.deps")
    if ok_deps then deps.show_once("images.nvim") end
  end
end

return M
