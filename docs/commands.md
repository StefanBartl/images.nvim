# Command reference

images.nvim registers exactly **one** user command — `:Image <subcommand>` —
built with [`lib.nvim.bindings.usercmd.composer`](https://github.com/StefanBartl/lib.nvim),
so dispatch, `<Tab>` completion and the cheatsheet all come from the same spec
and cannot drift apart. The name follows the `command` option.

For the one-line-per-route cheatsheet, see
[`BINDINGS.md`](BINDINGS.md#user-commands). This page carries the usage, the
arguments and the reasoning.

## Table of contents

- [Two things to know first](#two-things-to-know-first)
- [Showing](#showing)
- [Capturing](#capturing)
- [Converting](#converting)
- [Browsing and comparing](#browsing-and-comparing)
- [Diagnostics](#diagnostics)

## Two things to know first

**The range sits on the verb, not on a route.** `range = true` is declared once
for the whole spec, because the composer only honours the first `range` value
it finds — a mix would be misleading. Three routes read it: the bare `:Image`
becomes a gallery of the selected lines, `:'<,'>Image gallery` scopes the grid,
and `:'<,'>Image list` filters the picker. Everything else ignores a range.

**Most routes take an optional path, and default to the cursor.** Without an
argument, `show`, `info`, `replace`, `export`, `redact`, `ocr`, `scale`,
`optimise`, `convert`, `zen` and `draw` all act on the image link under the
cursor. Resolution order is: a Markdown link, a `<figure>`/`<figcaption>` block
(with markdown.nvim installed), [gopath.nvim](https://github.com/StefanBartl/gopath.nvim)'s
cursor resolver, then Vim's own `<cfile>`.

## Showing

### `:Image` · `:Image show [path]`

Show the image under the cursor, or `path`. With
`display.remote.enabled = true`, `path` may be an `http(s)` URL.

```vim
:Image                     " the link under the cursor
:Image show ./diagram.png
:'<,'>Image                " gallery of just the selected lines
```

Bare `:Image` with a range is a gallery, not a single image — the most common
case needs no subcommand either way.

### `:Image gallery [cols]` · `:'<,'>Image gallery [cols]`

Every image of the buffer (or the selection) side by side in a grid. The column
count is computed from the terminal width unless you give one.

- **Config:** `display.gallery_gap`.

### `:Image list` · `:'<,'>Image list`

Pick from every image link in the buffer (or the selection) and show the one
you choose. Uses lib.nvim's UI kit picker when available, else
`vim.ui.select`.

### `:Image next` · `:Image prev`

Jump to the next/previous image link and show it. Both wrap around, and both
take a count: `3<leader>in` lands three images on and wraps exactly as one step
would.

### `:Image zen [path]`

One image full-screen, in a **real editable window** rather than an overlay —
which is what lets it survive a hover popup opened alongside it. Redraws on
`WinResized`/`VimResized`, clears on `WinClosed`.

- **Config:** `display.zen.width` / `display.zen.height`.

### `:Image draw <position> [path]`

Draw at a named anchor in the current window: `full`, or one of the nine
corner/edge/center anchors from `images.scale.POSITIONS`. This is the
positioned single-shot primitive that `zen`, the hover float, `redact` and the
picker preview all delegate to internally.

```vim
:Image draw full
:Image draw top-right ./logo.png
```

Also available as Lua, and that is the form another plugin should use:

```lua
require("images").draw(target, position, path, opts)
```

`target` is a window handle, a buffer handle (resolved to whichever window
currently shows it), or `nil` for the current window. Pass `opts.defer = true`
when you opened the window in the same tick as the call — see
[architecture.md](architecture.md#what-it-takes-to-draw-reliably) for why that
matters.

### `:Image pin` · `:Image clear`

`pin` keeps the current image on screen instead of clearing it on the next
`display.clear_events` trigger. `clear` removes displayed images, releases a
pin, and closes a `:Image zen` window if one is open.

## Capturing

### `:Image paste [name]`

The everyday case for documentation: take a screenshot, run it, and the PNG is
written to `assets/<document>-<timestamp>.png` with `![](assets/…)` inserted at
the cursor. If a `Resources` or `Ressourcen` folder already exists next to the
document, that one is reused instead of creating `assets` alongside it
(`paste.existing_dir_names`). No image on the clipboard leaves no folder behind
either way.

`:Image paste {name}` uses `{name}` as the filename directly, skipping any
prompt. A count on `<leader>iv` forces the prompt instead — see
[configuration.md](configuration.md#paste).

### `:Image screenshot`

The same thing in one step: it takes the screenshot itself rather than reading
whatever is already on the clipboard, then continues exactly like `paste`.
Uses `screencapture -i` on macOS, `grim`+`slurp` or `maim -s` on Linux, and the
Windows Snipping Tool (`ms-screenclip:`) on Windows.

Windows is the least certain of the three: there is no documented way to have
the Snipping Tool write directly to a file, so this path waits for a new image
to appear on the clipboard, with a timeout
(`display.screenshot.windows_timeout_ms`, default 60 s). `:Image paste` remains
the proven two-step fallback.

### `:Image replace [path]`

Overwrite an existing image file with the clipboard image, keeping the link
that already points at it.

### `:Image redact [path]`

Censor mode: a full-screen window (like `zen`) with a selection grid over the
image.

| Key | Does |
| --- | --- |
| `v` / `<C-v>` then move, `<CR>` | mark a box |
| `u` (`3u`) | remove the last box, or three, clamped to what is there |
| `w` | burn every box in and write `photo.png` → `photo.redacted.png` |

The source file is never touched. Selection happens entirely in terminal cells
— a terminal has no pixel-precise mouse input at all — so each box is padded by
`display.redact.padding_cells` (default one cell): over-redacting is the safe
failure mode, under-redacting is not. Needs ImageMagick. Full rationale in
[FEATURES/CAPTURE.md](FEATURES/CAPTURE.md#why-boxes-are-padded-generously).

### `:Image orphans`

Find image files in `paste.dir` that no link in the buffer points to anymore,
and offer to delete them one at a time. Worth running before a commit that
touched a lot of images, not on every save.

> With markdown.nvim installed, the scan also sees HTML targets
> (`<img src="…">` inside a `<figure>`), so `orphans` reports *differently* —
> and more accurately — on a document full of captioned images.

## Converting

All four write a **new file** next to the source; the source is never edited in
place. The reasoning, and why a geometry is validated before ImageMagick sees
it, is in
[FEATURES/CAPTURE.md](FEATURES/CAPTURE.md#scale-optimise-convert--image-operations-as-file-operations).

### `:Image scale <size> [path]`

Resized copy, `photo.png` → `photo.scaled.png`. `size` is `50%`, `800x600`,
`800x`, `x600` or `800x600!` (the `!` ignores the aspect ratio). Needs
ImageMagick.

### `:Image optimise [path] [--quality=<n>]`

Smaller copy, `photo.png` → `photo.optimised.png`: metadata stripped, best
compression. A result that is **not** smaller is deleted and reported with both
sizes — handing you a larger file and calling it success would be a lie. Needs
ImageMagick.

### `:Image convert <format> [path]`

Copy in another format, same stem, `<Tab>`-completed from `extensions`.
`:Image convert pdf` takes the same route as `:Image export`. Needs
ImageMagick.

### `:Image export [path]`

Export as PDF next to the source. Routes through
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)'s `create()` API
when that plugin is installed — asynchronous, lossless via `img2pdf` if
available. Without it, the synchronous ImageMagick-only path.

### `:Image ocr [path] [--lang=<code>]`

Run the image through `tesseract` and open the recognised text in a `markdown`
scratch split below. A screenshot of an error message becomes something you can
search, yank, correct and translate. The buffer is named after the source image
and reused, so running OCR on the same file twice replaces the previous result
instead of stacking windows.

```vim
:Image ocr
:Image ocr --lang=deu+eng
:Image ocr -l deu ./scan.png
```

`--lang` / `-l` overrides `ocr.lang` for this run. Needs `tesseract` **plus**
the language data for whatever language is asked for — those install
separately. See
[FEATURES/CAPTURE.md](FEATURES/CAPTURE.md#ocr--read-the-text-out-of-an-image),
including why a Windows install is often present but not on PATH.

### `:Image info [path]`

Format, pixel dimensions and file size. Dimensions need ImageMagick; without
it, format and size are still shown.

## Browsing and comparing

### `:Image pickers [cfile|cwd|path] [dir]`

Browse every image under `cfile` (the directory of the file under the cursor),
`cwd`, or an explicit `dir`. With [snacks.nvim](https://github.com/folke/snacks.nvim)
installed, each entry gets a live image preview; without it, a plain list.
`<Tab>` multi-selects in the snacks picker, and confirming more than one shows
them as a gallery instead of opening the first.

- **Config:** `display.browse_exclude`, `display.browse_max_entries`.

### `:Image compare [cfile|cwd|path] [dir]`

Pick two images from the same kind of scan and view them side by side. With
ImageMagick they are scaled to their **true relative size**, which is the
point: shown at equal size, two exports would hide that one came out at twice
the pixel dimensions of the other.

## Diagnostics

### `:Image check`

Re-run the terminal capability probe and report whether OSC 1337 is getting
through. This is the one question `:checkhealth images` cannot answer from
inside Neovim.

### `:Image calibrate`

Measure how this terminal actually places an image, interactively. It draws a
generated test card that exactly fills a framed window; `hjkl`/arrows nudge it
one cell per press, `+`/`-` adjust `display.cell_aspect` in 0.01 steps, `r`
resets, `<CR>` accepts, `q` cancels. The result is offered for saving under
`stdpath("data")` and applies on every start.

Run it once per terminal setup, not per project — and again on a different
machine, even one running the same synced config. See
[FEATURES/DISPLAY.md](FEATURES/DISPLAY.md#placement-calibration) for how the
tool works and
[architecture.md](architecture.md#placement-is-whole-cell-and-that-is-the-protocol)
for why it has to exist.

### `:Image debug <mode> [path]`

Measure image placement when something lands in the wrong spot, rather than
guessing at it.

| Mode | Answers |
| --- | --- |
| `report` | which coordinates were actually sent, per draw |
| `columns` | is this a constant offset (`terminal_padding` can absorb it) or a scaling one (it cannot) |
| `float` | is the window where Neovim claims it is |

The failure modes these three were built to tell apart turned up two real bugs.
