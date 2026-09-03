---@module 'images.integrations.picker'
---@brief The draw surface a foreign picker previews images and PDF pages
--- against (a soft, opt-in integration).
---@description
--- `images.browse` (`:Image pickers`) is images.nvim's own picker: it already
--- knows every one of its items is an image and binds straight to
--- snacks.picker. This module is the inverse case — a *host's* picker lists
--- whatever it lists (files, git status, a smart search), and for the entries
--- that happen to be images it wants the real picture in its own preview
--- window instead of the binary bytes. Such a host needs exactly three things,
--- and this module is those three things:
--- >
---   available()              -- may I take the preview over at all?
---   is_previewable(path)     -- is this entry one of yours?
---   preview(winid, file)     -- then draw it into that window
--- <
--- pickers.nvim consumes precisely this surface (its own
--- `pickers.integrations.images` is the counterpart), which is the same
--- division of labour `images.integrations.menu` already has with nvzone/menu:
--- the host composes, images.nvim supplies. Nothing here is images.nvim-
--- specific to a host — a foreign picker never has to know about
--- `images.anchor`, `images.terminal` or the OSC 1337 pitfalls behind them.
---
--- **A PDF entry is one of ours too, when it can be.** `is_previewable`
--- answers yes for a `.pdf` whenever pdfport.nvim and poppler's `pdftoppm` are
--- both there; `preview` then rasterizes the first page through `images.pdf`
--- and draws *that*, so from the draw down there is no PDF any more, only a
--- PNG like every other. A host writes no PDF code of its own and gets no
--- second surface to call: `is_image` stays, unchanged, for a host that wants
--- the narrower question.
---
--- **Why `available()` is conservative where the rest of the plugin is not.**
--- Everywhere else a failed capability check warns and draws anyway (see
--- `images.guard`): detection is a heuristic over environment variables,
--- because OSC 1337 has no capability query, and a false negative must not
--- break a working setup. A foreign preview window is the one place where that
--- reasoning inverts. Taking it over and drawing nothing leaves the host with
--- an empty window instead of the working text preview it would have shown by
--- itself — the fallback is *better* than the attempt here, which is never
--- true for `:Image show`. So `available()` answers strictly, and a user on an
--- unrecognised terminal gets their preview back via the documented escape
--- hatch, `display.assume_supported = true`. `is_pdf` is strict for the same
--- reason and about the other half of the question: it says no without a
--- rasterizer, so an unrasterizable PDF stays the host's to preview.
---
--- `preview()` itself does not re-check: a host that asked and got a "no" and
--- draws anyway has made a decision, and this module is not the place to
--- overrule it. It goes through `images.draw`, the public draw entry point, so
--- it warns through `images.guard` and reports a failed draw through `notify`
--- exactly as every other draw path does — a host gets images.nvim's own error
--- messages without having to relay them itself.
---
--- **The overlay outlives the window that asked for it.** OSC 1337 has no
--- image ids; what has been drawn cannot be removed individually, only
--- repainted away (`images.terminal.clear`). A picker that closes takes its
--- preview window with it but not the image drawn over it, so every draw here
--- arms a one-shot `WinClosed` for that window. Hosts should still call
--- `M.clear()` when the selection moves from an image to a non-image entry:
--- the window stays open in that case, and the picture would otherwise sit on
--- top of the text preview that follows it.
---
--- **A rasterization outlives the selection that asked for it too, and that
--- one has to be cancelled rather than repainted.** A page takes 150–400 ms to
--- produce the first time; selection in a picker moves faster than that. Every
--- call here therefore takes a ticket, and a page that comes back holding a
--- stale one is dropped instead of drawn — otherwise the PDF two entries up
--- would land on top of whatever is being previewed by the time it is ready.
--- `M.clear()` invalidates the outstanding ticket as well, which is what makes
--- a host's "moved to a text entry" also mean "and never mind that page".

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@type integer The ticket every preview request takes; see the module docs.
local generation = 0

---@return integer
local function bump()
  generation = generation + 1
  return generation
end

--- Whether this terminal can show images at all — the question a host asks
--- before it replaces its own previewer with this one. See the module docs for
--- why the answer is strict here and lenient everywhere else.
---@return boolean
function M.available()
  local terminal = require("images.terminal")
  if not terminal.available() then return false end
  return terminal.capability(cfg().display.assume_supported).ok
end

--- Whether a path names an image, judged by the configured `extensions` alone
--- (no file read, no mime lookup) — cheap enough for a host to call once per
--- entry while the selection moves.
---@param path string|nil
---@return boolean
function M.is_image(path)
  if type(path) ~= "string" or path == "" then return false end
  return require("images.resolve").is_image(path)
end

--- Whether a path names a PDF *this machine can rasterize* — the extension
--- plus pdfport.nvim plus `pdftoppm`, because a yes here is a promise to draw
--- and there is no point promising what cannot be produced. See `images.pdf`.
---@param path string|nil
---@return boolean
function M.is_pdf(path)
  if type(path) ~= "string" or path == "" then return false end
  local pdf = require("images.pdf")
  return pdf.is_pdf(path) and pdf.available()
end

--- Whether `preview` would take this entry: an image, or a PDF that can be
--- rasterized. The question a host asks once per entry.
---@param path string|nil
---@return boolean
function M.is_previewable(path)
  return M.is_image(path) or M.is_pdf(path)
end

--- The configured image extensions, without the leading dot. For a host that
--- wants to *list* images rather than recognise them — an `fd -e png -e jpg …`
--- built from the same list the preview will accept. PDFs are deliberately not
--- in it: whether one can be drawn is a fact about the machine rather than
--- about the configuration, and `is_pdf` is the function that knows it.
---@return string[] a copy; the caller may modify it freely
function M.extensions()
  return vim.deepcopy(cfg().extensions)
end

--- Remove the drawn image again (a no-op when nothing is showing), and drop
--- any page still being rasterized for an earlier selection.
---@return nil
function M.clear()
  bump()
  require("images.terminal").clear()
end

--- Clear the overlay once `winid` is gone. Re-armed on every draw with a
--- cleared group, so the pending cleanup always refers to the window that was
--- drawn into last, not to a stack of windows that have long since closed.
---@param winid integer
---@return nil
local function arm_clear(winid)
  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    M.clear()
  end, {
    group = autocmd.group("images.integrations.picker", true),
    pattern = tostring(winid),
    once = true,
    desc = "images.integrations.picker: clear the overlay when the preview window closes",
  })
end

---@class Images.Picker.PreviewOpts
---@field position string|nil where inside the window, see `images.scale.POSITIONS`; default `"full"`
---@field scale number|nil 0 < scale <= 1; ignored for `position = "full"`
---@field inset integer|nil margin in cells all round; nil = `display.draw_inset`
---@field defer boolean|nil `vim.schedule` before drawing; default `true`, which is what a picker preview needs — the host has usually just reset or refilled that window in the same tick (see `images.anchor`)
---@field on_done fun(ok: boolean, err: string|nil)|nil runs exactly once, after the deferred draw has settled
---@field on_ready fun()|nil runs once, immediately before the draw is scheduled — see `M.preview`
---@field page integer|nil PDF entries only: which page; default `pdf.page`
---@field dpi integer|nil PDF entries only: rasterization resolution; default `pdf.dpi`

--- The draw itself, once there is a picture on disk to draw — an image entry's
--- own file, or a rasterized page standing in for one.
---@param winid integer
---@param file string
---@param opts Images.Picker.PreviewOpts
---@return boolean ok
---@return string|nil err
local function draw(winid, file, opts)
  -- `images.draw` rather than `images.anchor.draw`: the public entry point
  -- carries the capability guard and the error notification, which a foreign
  -- host would otherwise have to reimplement. Its "resolve the path, or fall
  -- back to the image under the cursor" behaviour cannot bite here -- `file`
  -- has just been established to be a non-empty image path.
  local ok, err = require("images").draw(winid, opts.position or "full", file, {
    scale = opts.scale,
    inset = opts.inset,
    defer = opts.defer ~= false,
    on_done = opts.on_done,
  })

  -- Only once something is actually on its way to the screen: a cleanup armed
  -- for a draw that never happened would repaint on the next window close for
  -- no reason.
  if ok then arm_clear(winid) end

  return ok, err
end

--- Draw `file` into a host's preview window.
---
--- The return value answers "was the draw accepted", not "is the image on
--- screen": with the default `defer = true` the draw happens in the next tick,
--- and its outcome arrives through `opts.on_done`. That is what a host wants
--- to branch on anyway — `false` means *this entry is not mine, keep your own
--- preview*, and comes back synchronously, before the host has painted
--- anything.
---
--- The two rejections that produce it are the two a host cannot check for
--- itself without knowing images.nvim's configuration: a window that is gone
--- (a selection can move faster than a preview draws) and a path that is
--- neither an image by *this* configuration's `extensions` nor a PDF this
--- machine can rasterize.
---
--- **A PDF is accepted before its page exists.** `true` comes back at once and
--- the rasterization runs behind it, so the window is briefly empty the first
--- time a given page is asked for (afterwards it is cached on disk and the
--- draw is immediate — see `images.pdf`). A host that wants to fill that
--- moment can ask `is_pdf` and put a line in its own buffer, and take it down
--- again in `opts.on_ready`, which runs once the page exists and immediately
--- before the draw is scheduled.
---
--- **Taking it down is not optional, and the timing is the reason
--- `on_ready` exists at all.** A drawn image covers the box it was given, and
--- that box is shaped like the picture rather than like the window (see
--- `images.anchor`) — so for a portrait page in a wide preview window,
--- everything the host wrote outside a narrow centred strip stays visible
--- beside the picture. `on_done` is too late to fix that: it runs *after* the
--- draw, and editing the buffer then makes Neovim repaint the very cells the
--- image occupies. `on_ready` runs a tick earlier, and `images.terminal.draw`
--- flushes pending repaints before the payload goes out, so the host's edit
--- lands first and the picture lands on top of it.
---
--- A page that fails to rasterize reports through `opts.on_done` and *nothing
--- else*: no notification, because a selection moving over a broken PDF would
--- otherwise say so once per keypress, and because the host has a working
--- answer of its own to fall back to. `on_ready` does not run in that case,
--- nor for a draw that was refused or superseded — a host's placeholder is
--- then still the truth on screen until the host replaces it.
---@param winid integer the host's preview window
---@param file string absolute path to an image or PDF file
---@param opts Images.Picker.PreviewOpts|nil
---@return boolean ok
---@return string|nil err
function M.preview(winid, file, opts)
  opts = opts or {}

  if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then
    return false, "not a valid window: " .. tostring(winid)
  end

  -- Before either branch, and before any early return: a request that turns
  -- out not to be ours still supersedes a page still being rasterized for the
  -- entry the selection has just left.
  local ticket = bump()

  if M.is_image(file) then
    if opts.on_ready then opts.on_ready() end
    return draw(winid, file, opts)
  end

  if M.is_pdf(file) then
    require("images.pdf").page_png(file, { page = opts.page, dpi = opts.dpi }, function(png, err)
      if not png then
        if opts.on_done then opts.on_done(false, err or "could not rasterize the page") end
        return
      end
      if ticket ~= generation or not vim.api.nvim_win_is_valid(winid) then
        if opts.on_done then opts.on_done(false, "superseded by a newer preview") end
        return
      end
      if opts.on_ready then opts.on_ready() end
      draw(winid, png, opts)
    end)
    return true
  end

  -- A `.pdf` that got this far is one without a rasterizer — worth saying so,
  -- because "not an image" would send a host looking at its extension list.
  if require("images.pdf").is_pdf(file) then return false, "a PDF page needs pdfport.nvim and poppler's pdftoppm" end

  return false, "not an image: " .. tostring(file)
end

return M
