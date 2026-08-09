<pre>
  ___
 |_ _|_ __  __ _ __ _ ___ ___
  | || '  \/ _` / _` / -_|_-<
 |___|_|_|_\__,_\__, \___/__/
                |___/
        show images inside Neovim, on any terminal that speaks OSC 1337
</pre>

![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Made%20with-Lua-2C2D72?logo=lua&logoColor=white)
![Depends](https://img.shields.io/badge/depends-lib.nvim-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-lightgrey)

---

> Writing documentation with a lot of links and images?
> [markdown.nvim](https://github.com/StefanBartl/markdown.nvim) resolves the
> link targets that this plugin renders.

## Table of Contents

- [Why not snacks.image or image.nvim](#why-not-snacksimage-or-imagenvim)
- [Quickstart](#quickstart)
- [Usage](#usage)
- [Configuration](#configuration)
- [Integrations](#integrations)
- [Optional external tools](#optional-external-tools)
- [Documentation](#documentation)
- [Development](#development)

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into your document. Built on
[lib.nvim](https://github.com/StefanBartl/lib.nvim) as a deliberate shared
dependency.

```
:Image                     show the image under the cursor
:'<,'>Image                gallery of just the selected lines
:Image gallery             every image in the buffer, side by side
:Image paste               clipboard screenshot → file next to the document + link
:Image screenshot          take a screenshot interactively, skipping the clipboard step
:Image next / prev         walk through the images of the buffer
:'<,'>Image list           pick from the images in the selection
:Image orphans             images in paste.dir that nothing links to anymore
:Image pickers cwd         browse every image under cwd, live preview with snacks.picker
:Image zen                 the image under the cursor, full-screen, in a real window
:Image compare cwd         pick two images, view side by side at their true relative size
```

## Why not snacks.image or image.nvim

Both speak only the Kitty graphics protocol. On native Windows Neovim running
in WezTerm, Kitty APC sequences (`ESC _G`) are never drawn when they come from
Neovim — the very same sequences work from a raw shell, so the difference is
introduced by Neovim's output layer. That makes both plugins unusable there,
regardless of configuration.

images.nvim uses the iTerm2 protocol (OSC 1337) instead, which works
reliably. Four details that matter, all of them learned the hard way:

- Output goes through `vim.api.nvim_ui_send`, not `io.stdout:write` — the
  latter only draws once per terminal session.
- The cursor is saved and positioned first (`ESC[s` / `ESC[<row>;<col>H` /
  payload / `ESC[u`). Without that the image lands below the statusline and
  pushes it up.
- `width` and `height` are given in **cells**, together with
  `preserveAspectRatio=1`. The terminal does the scaling, so the pixel size of
  a cell never has to be known — which is exactly where snacks.image breaks on
  Windows, since its `ioctl(TIOCGWINSZ)` path cannot work there.
- Drawing is ordered against Neovim's own repaint, in two places.
  `nvim_ui_send` writes to the terminal immediately, while Neovim only paints
  once control returns to the main loop. Open a window and draw into it in the
  same tick, and Neovim paints that window's cells over the image right after
  it was sent — popup visible, image gone or half gone. So `images.terminal.
  draw` flushes anything already pending before the payload goes out, **and**
  every path that opens a window first (`zen`, `hover_float`, `redact`) defers
  its draw by one tick — a flush before sending cannot cover the repaint that
  opening the window itself causes. `show`/hover need neither: they draw over
  existing text without creating a window.

Before the first draw the terminal is checked against the small set that
implements OSC 1337 (WezTerm, iTerm2, Konsole), detected from environment
variables. An unknown terminal produces a warning **once per session** and the
image is still drawn — the protocol has no capability query, so this is a
heuristic, and a false negative must not break a working setup. Silence it
with `display.assume_supported = true`; `:Image check` re-runs the detection.

Inline images in the text flow are not possible on WezTerm: they require
Unicode placeholders, which only Kitty and Ghostty implement and neither ships
for Windows. images.nvim draws over the text instead, and clears on the next
cursor move — this is `display.hover_mode = "overlay"`, the default.

Setting `display.hover_mode = "float"` shows the same hover/`:Image show`
image in a small, unfocused floating window under the cursor instead — a
real window Neovim owns and repaints over, rather than an escape-sequence
overlay drawn on top of the text. Same lifecycle (closes on the next
`display.clear_events` event, `:Image pin` holds it), same underlying draw
call, just a different container. Only affects the single-image path — the
gallery keeps its own layout either way.

SVG is the one format WezTerm cannot decode at all — everything else
(PNG/JPEG/GIF/WebP/BMP) it handles itself. With ImageMagick installed, an
`.svg` file is rasterized to a cached PNG before drawing; without it, opening
one reports a clear error instead of failing silently. Together with
`:Image export` (unless `pdfport.nvim` is installed, see below), `:Image
redact` and the ASCII fallback (below), these are deliberately the *only*
four places ImageMagick is a requirement rather than an improvement — see
[Configuration](#configuration).

When the terminal check fails, `:Image show`/hover fall back to a colored
block-character rendering instead of the (silently ineffective) OSC 1337
sequence — solid `█` cells with a per-cell true-color foreground sampled
straight from the image, the same technique graphics-protocol-less terminal
viewers like `chafa`/`viu` use, rather than a brightness character ramp
(`" .:-=+*#%@"`). This needs ImageMagick to read the pixels (`display.
ascii_fallback`, `images.ascii`) — a fourth deliberate exception alongside
SVG/export/redact, see [Configuration](#configuration). Only the
single-image path (`:Image show`/hover) gets it, same scope boundary as
remote images below; set `display.ascii_fallback.enabled = false` to turn it
off and keep the old silent-no-op-with-a-warning behavior instead.

Remote images (`http://…`/`https://…`) are supported by `:Image show <url>`
and by hovering a markdown link that points at one, but **off by default**:
set `display.remote.enabled = true` first. This mirrors what email clients
have done for years ("load remote images") — a document merely being opened
should not silently make an outbound network request just because it
contains an image link. Downloads are cached by URL, with a size and time
limit (`display.remote.max_bytes`/`timeout_ms`). `:Image gallery`, `compare`,
`pickers` and `zen` do not resolve remote images yet — only the single-image
path does.

## Quickstart

Requires Neovim 0.10+ (for `vim.base64`) with API level 14 (for
`nvim_ui_send`), and [lib.nvim](https://github.com/StefanBartl/lib.nvim).

```lua
{
  "StefanBartl/images.nvim",
  ft = { "markdown", "vimwiki", "norg", "text" },
  dependencies = { "StefanBartl/lib.nvim" },
  opts = {
    -- optional, see Configuration
  },
},
```

Run `:checkhealth images` to verify that your terminal, clipboard tool and
dependencies are in place.

## Usage

| Command | What it does |
| --- | --- |
| `:Image` | Show the image under the cursor |
| `:Image show [path]` | Show a specific file, or the one under the cursor; `path` may be a URL if `display.remote.enabled` |
| `:Image list` | Pick from every image link in the buffer |
| `:'<,'>Image list` | …restricted to the selected lines |
| `:Image gallery [cols]` | Show every image of the buffer side by side in a grid |
| `:Image next` / `prev` | Jump to the next/previous image and show it |
| `:Image info [path]` | Format, dimensions and file size |
| `:Image paste [name]` | Save the clipboard image next to the document and insert the link; with `name`, use that filename directly instead of asking/templating |
| `:Image screenshot` | Take a screenshot interactively and insert the link — skips the clipboard step |
| `:Image replace [path]` | Overwrite an existing image with the clipboard, keep the link |
| `:Image export [path]` | Export an image as PDF, next to the source file — via `pdfport.nvim` if installed, else requires ImageMagick |
| `:Image redact [path]` | Open a censor mode: mark boxes (Visual mode + `<CR>`), `w` blacks them out into a new file — requires ImageMagick |
| `:Image orphans` | Find images in `paste.dir` that no link points to, offer to delete |
| `:Image pickers [cfile\|cwd\|path] [dir]` | Browse images under cfile/cwd/an explicit dir; live preview with snacks.picker, falls back to a plain list. `<Tab>` multi-selects (snacks), confirming shows them as a gallery instead of one image |
| `:Image zen [path]` | Show one image full-screen, in a real editable window — survives a snacks hover popup open alongside it |
| `:Image draw <position> [path]` | Draw an image at a named position ("full", "center", "top-left", …) in the current window — the reliable, positioned single-shot primitive behind zen/hover/redact, also available as `images.draw()` for other plugins |
| `:Image compare [cfile\|cwd\|path] [dir]` | Pick two images from a scan, view side by side; with ImageMagick, scaled proportionally so a small icon doesn't look the same size as a large photo |
| `:Image pin` | Keep the image on screen instead of clearing on cursor move |
| `:Image check` | Report whether this terminal can display images |
| `:Image clear` | Remove displayed images (and a `:Image zen` window, if open) |

In markdown buffers, `<leader>im` shows the image under the cursor, `<leader>ig`
opens the gallery, `<leader>in`/`<leader>ip` walk through the images,
`<leader>iv` pastes from the clipboard, `<leader>is` takes a screenshot, and a
double-click on a link shows the image. With
[which-key](https://github.com/folke/which-key.nvim) installed, `<leader>i`
shows up as a named group — detected from whichever of the above keys share a
common prefix, so a fully remapped set of keys still groups correctly. A
double-click that does not hit an image link falls through to the normal word
selection.

`:Image paste` is the everyday case for documentation: take a screenshot, run
it, and the PNG is written to `assets/<document>-<timestamp>.png` with
`![](assets/…)` inserted at the cursor — unless a `Resources` or
`Ressourcen` folder already exists next to the document, in which case that
one is reused instead of creating `assets` alongside it (see
`paste.existing_dir_names` below). No image on the clipboard leaves no
folder behind either way. `:Image paste {name}` uses `{name}` directly as
the filename instead. `:Image screenshot` collapses this
further into one step — it takes the screenshot itself instead of reading
whatever is already on the clipboard, then continues exactly like `:Image
paste`. Uses `screencapture -i` on macOS, `grim`+`slurp` or `maim -s` on
Linux, and the Windows Snipping Tool (`ms-screenclip:`) on Windows — the
least certain of the three, since there is no documented way to have it write
directly to a file; this plugin waits for a new image to appear in the
clipboard instead, with a timeout. `:Image paste` remains the unchanged,
proven two-step fallback if that doesn't work for you.

`:Image redact` opens a censor mode: a full-screen window (like `:Image
zen`) with a selection grid over the image. Enter Visual mode (`v`/`<C-v>`),
move to the opposite corner of what needs blacking out, `<CR>` marks it —
repeat for as many boxes as needed, `u` removes the last one, `w` burns them
in (ImageMagick) and writes a new file (`photo.png` → `photo.redacted.png`);
the source file is never touched. Selection happens entirely in terminal
cells — a redacted image is drawn without pixel-precise mouse input being
available in a terminal at all, so the box is sized generously on purpose
(configurable via `display.redact.padding_cells`, default one cell of
margin): over-redacting is the safe failure mode, under-redacting is not.
See [docs/ROADMAP/REDACT.md](docs/ROADMAP/REDACT.md) for the full design
rationale.

`:Image draw <position> [path]` (Lua: `images.draw(target, position, path,
opts)`) draws reliably at a named spot in a window — `"full"` fills it,
`"top-left"`/`"center"`/`"bottom-right"`/… anchor a smaller, scaled box (see
`images.scale`'s `POSITIONS` list for the full nine anchors plus `"full"`).
`target` is a window handle, a buffer handle (resolved to whichever window
currently shows it), or nil for the current window — the command always
targets the current one. This is the one place that actually knows how to
draw into a window and have it stick: `:Image zen`, the hover float, redact,
and the picker preview all delegate to it internally, so a window opened in
the same tick as the draw call (`opts.defer = true`) is handled correctly
without every caller re-solving the same timing problem (see
`lua/images/anchor.lua`'s module doc for why that problem exists at all).

## Configuration

```lua
require("images").setup({
  command = "Image",
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" }, -- svg needs ImageMagick to draw
  display = {
    max_cols = 60,   -- in terminal cells, not pixels
    max_rows = 25,
    gallery_gap = 1, -- cells between gallery tiles
    hover_mode = "overlay", -- "float" shows a small window instead of drawing over the text
    assume_supported = false, -- true silences the "unknown terminal" warning
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    browse_exclude = { ".deps", "node_modules" }, -- dirs :Image pickers skips (".git" is always skipped)
    zen = { width = 0.9, height = 0.85 },          -- :Image zen window size, as a fraction of the editor
    remote = {
      enabled = false,             -- true allows :Image show <url> / hover to download images
      timeout_ms = 10000,
      max_bytes = 20 * 1024 * 1024,
    },
    screenshot = {
      -- Windows only: how long / how often :Image screenshot polls the
      -- clipboard for a new image after launching the Snipping Tool.
      windows_timeout_ms = 60000,
      windows_poll_interval_ms = 600,
    },
    redact = {
      padding_cells = 1, -- safety margin around each marked box, in cells
    },
    ascii_fallback = {
      enabled = true, -- block-character rendering when the terminal check fails; needs ImageMagick
    },
  },
  paste = {
    dir = "assets",              -- "" puts the file next to the document
    existing_dir_names = { "Resources", "Ressourcen" }, -- reused instead of `dir` if already present; {} disables
    name_template = "%s-%d.png", -- document stem, timestamp
    link_template = "![](%s)",
    ask_alt_text = false,        -- true prompts for alt text before inserting the link
    alt_link_template = "![%s](%s)",
    ask_filename = false,        -- true prompts for a name, prefilled with the template
  },
  keymaps = {
    show = "<leader>im",  -- every entry accepts false to disable it
    gallery = "<leader>ig",
    next = "<leader>in",
    prev = "<leader>ip",
    paste = "<leader>iv",
    screenshot = "<leader>is",
    double_click = true,
    filetypes = { "markdown", "vimwiki", "norg", "text" },
  },
})
```

`paste.ask_alt_text = true` prompts for alt text before inserting the link
(via lib.nvim's UI kit when available), producing `![alt](path)` instead of
`![](path)`. Cancelling the prompt still inserts the link, just without alt
text — the file is already on disk by then, and a lost link would be the
worse surprise.

`paste.ask_filename = true` prompts for a filename before writing the
clipboard image, prefilled with what `paste.name_template` would have
produced. Any path component in the answer is dropped — only the name
itself is used — and the extension is always forced to `.png`, since that is
what gets written regardless of what you type. Cancelling here does nothing
at all: unlike the alt-text prompt, nothing has been read from the clipboard
yet at this point, so cancel means cancel.

`:Image paste {name}` sanitizes `{name}` the same way and uses it directly,
skipping the prompt outright — a name given on the command line takes
priority over `paste.ask_filename`.

A statusline segment:

```lua
{ require("images").statusline }  -- "" when nothing is shown, else an icon
```

## Integrations

`markdown.nvim` is used for link resolution when present, falling back to an
internal resolver otherwise — a soft dependency, never required. The
relationship also runs the other way: `markdown.nvim`'s `mi` prefers
images.nvim as its in-Neovim preview provider (over snacks.nvim/image.nvim,
both Kitty-only), and its `:Markdown links show` reuses
`images.browse.draw_in_window()` for a live per-item image preview when
`snacks.picker` is also installed. `draw_in_window()` is itself a thin,
name-preserved wrapper around `images.draw()` now — a new consumer should
reach for `images.draw(target, position, path, opts)` directly instead,
`draw_in_window` stays only for that existing call site.

`lib.nvim` provides the `:Image` command grammar (`usercmd.composer`), the
picker used by `:Image list`, and the `kit.compare` component behind
`:Image compare`; without its UI kit the picker falls back to `vim.ui.select`.

[snacks.nvim](https://github.com/folke/snacks.nvim)'s picker is a soft
dependency for `:Image pickers`: with it installed, browsing shows a live
image thumbnail per entry (a custom preview function, not snacks.image's own
Kitty-only one — see "Why not snacks.image or image.nvim" above); without it,
`:Image pickers` falls back to a plain list with no preview.

`filetree.nvim` uses this plugin as the first backend of its preview feature,
and `open.nvim` routes `:Open image` here. See
[docs/ROADMAP/CROSS-PLUGIN.md](docs/ROADMAP/CROSS-PLUGIN.md) for what else is
possible across the sibling plugins.

## Optional external tools

ImageMagick unlocks `:Image info`'s dimensions, `:Image compare`'s relative
scaling, SVG display, and is required outright for `:Image redact`;
`chafa` is the terminal-image fallback. `:Image export` needs ImageMagick
too, *unless* [`pdfport.nvim`](https://github.com/StefanBartl/pdfport.nvim)
is installed — then the export routes through pdfport's `create()` API
instead (asynchronous, lossless via `img2pdf` if available, otherwise
`magick` through pdfport's own fallback chain). Soft dependency, `pcall`'d;
without pdfport.nvim the previous synchronous `magick`-only path is
unchanged. Declared, with the reasoning per
tool, in [`docs/install.json`](docs/install.json) — parsed by
[lib.nvim](https://github.com/StefanBartl/lib.nvim)'s
[`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md),
which this plugin already depends on:

- The first time `setup()` runs after installing images.nvim, a popup shows
  what's missing and why (once, ever — see `:help lib.nvim-deps-first_run`).
- `:Lib deps show images.nvim` shows the same report at any time.
- `:Lib deps install images.nvim` composes and confirms an install command
  for your OS's package manager.
- Also folded into `:checkhealth images`.
- Disable it **right in this plugin's own spec**:
  `require("images").setup({ deps_popup = false })`.
  `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) /
  `vim.g.lib_nvim_deps_disabled_plugins = { "images.nvim" }` also still
  work, for turning it off without touching any plugin's config.

## Documentation

- `:h images` — vimdoc reference
- [docs/BINDINGS.md](docs/BINDINGS.md) — every keymap, user command and autocmd
- [docs/map/](docs/map/) — generated module map ([documentation.nvim](https://github.com/StefanBartl/documentation.nvim))
- [docs/ROADMAP/](docs/ROADMAP/) — planned features and cross-plugin ideas

## Development

```bash
nvim --headless -u NONE -l TESTS/run.lua        # tests
nvim --headless -l scripts/gen_map.lua          # regenerate the module map
nvim --headless -l scripts/gen_map.lua --check  # verify it, write nothing
luacheck lua/ plugin/ scripts/ TESTS/ --globals vim
```

The suite covers the side-effect-free modules only — grid layout, link
detection, metadata formatting, config merging. Anything that draws needs a
terminal with a graphics protocol and cannot be checked headless, which is
why those parts are separated from the rendering in the first place.
`scripts/gen_map.lua` enforces that split as a layer rule, so it stays a
checked invariant rather than a note in a document.

Install the pre-commit hook once per clone:

```bash
git config core.hooksPath scripts/hooks
```
