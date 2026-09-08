# Configuration

Every `setup()` option, its default, and what it is for. `setup()` merges
your table over the defaults in `lua/images/config/DEFAULTS.lua`, which is the
single source of truth — this page is the prose version of it, and the type
definitions live in `lua/images/@types/init.lua`.

Nothing here is required: `opts = {}` is a complete configuration.

## Table of contents

- [The whole default table](#the-whole-default-table)
- [Top level](#top-level)
- [display](#display)
- [paste](#paste)
- [ocr](#ocr)
- [pdf](#pdf)
- [menu](#menu)
- [keymaps](#keymaps)
- [Statusline](#statusline)

## The whole default table

```lua
require("images").setup({
  command = "Image",
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" },
  deps_popup = true,
  display = {
    max_cols = 60,
    max_rows = 25,
    cell_aspect = 0,
    draw_inset = 1,
    terminal_padding = { row = 0, col = 0 },
    gallery_gap = 1,
    hover_mode = "overlay",
    assume_supported = false,
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    browse_exclude = { ".deps", "node_modules" },
    browse_max_entries = 20000,
    zen = { width = 0.9, height = 0.85 },
    remote = {
      enabled = false,
      timeout_ms = 10000,
      max_bytes = 20 * 1024 * 1024,
    },
    screenshot = {
      windows_timeout_ms = 60000,
      windows_poll_interval_ms = 600,
    },
    redact = {
      padding_cells = 1,
    },
    ascii_fallback = {
      enabled = true,
      levels = 8,
      cells = "sextant",
    },
    gopath_fallback = true,
  },
  paste = {
    dir = "assets",
    existing_dir_names = { "Resources", "Ressourcen" },
    name_template = "%s-%d.png",
    link_template = "![](%s)",
    ask_alt_text = false,
    alt_link_template = "![%s](%s)",
    ask_filename = false,
  },
  ocr = {
    lang = "eng",
    args = {},
    bin = nil,
  },
  pdf = {
    enabled = true,
    page = 1,
    dpi = 120,
  },
  menu = {
    enable = true,
  },
  keymaps = {
    show = "<leader>im",
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

## Top level

| Key | Default | What it does |
| --- | --- | --- |
| `command` | `"Image"` | Name of the single user command. Every route in [commands.md](commands.md) follows it |
| `extensions` | `png jpg jpeg gif webp bmp svg` | Which files count as images — for link resolution, the pickers, and `:Image convert`'s target list. `svg` needs ImageMagick to draw, see [architecture.md](architecture.md#the-four-costs-and-where-each-one-shows-up) |
| `deps_popup` | `true` | The one-off "which CLI tools does this want, and why" popup on the first `setup()` after installation, via `lib.nvim.deps`. `false` disables it for this plugin without touching any `vim.g` |

## display

| Key | Default | What it does |
| --- | --- | --- |
| `max_cols` / `max_rows` | `60` / `25` | The largest box an image is drawn into, **in terminal cells, not pixels**. The terminal scales into that box itself, which is why the pixel size of a cell never has to be known |
| `cell_aspect` | `0` | Pixel aspect ratio (width/height) of one cell. `0` uses the 0.5 assumption from `images.scale`. Cannot be detected; `:Image calibrate` measures it with you |
| `draw_inset` | `1` | Cells of margin kept free all round. The default is robustness, not looks — see [Placement](#placement-draw_inset-terminal_padding-cell_aspect) below. `0` draws flush |
| `terminal_padding` | `{ row = 0, col = 0 }` | Whole-cell draw offset for terminals whose window padding is not cell-aligned. Negative values move the image up/left |
| `gallery_gap` | `1` | Cells between two gallery tiles |
| `hover_mode` | `"overlay"` | `"overlay"` draws over the text and clears on the next `clear_events` event; `"float"` shows the same image in a small unfocused window instead. Affects `:Image show`/hover only — the gallery keeps its own layout either way |
| `assume_supported` | `false` | `true` silences the "unknown terminal" warning. It changes nothing about drawing — see [architecture.md](architecture.md#detection-is-a-heuristic-and-stays-one) |
| `clear_events` | `CursorMoved`, `CursorMovedI`, `InsertEnter`, `BufLeave`, `WinScrolled` | The events that take a displayed image down again. `:Image pin` suspends them for the current image |
| `browse_exclude` | `{ ".deps", "node_modules" }` | Directory names `:Image pickers` skips while scanning. `.git` is always skipped |
| `browse_max_entries` | `20000` | Upper bound on entries that scan visits. A safety net against a `cwd` that turns out to be your home directory, not an error: what was found so far is still shown |
| `zen.width` / `zen.height` | `0.9` / `0.85` | Size of the `:Image zen` window, as a fraction of the editor |
| `gopath_fallback` | `true` | Ask [gopath.nvim](https://github.com/StefanBartl/gopath.nvim)'s cursor resolver about a bare filesystem path before falling back to Vim's `<cfile>`. A no-op without gopath.nvim; `false` disables it even with it installed |

### Placement: `draw_inset`, `terminal_padding`, `cell_aspect`

These three are one topic, and the reason they exist at all is in
[architecture.md](architecture.md#placement-is-whole-cell-and-that-is-the-protocol).
In short:

- `draw_inset` absorbs the **sub-cell remainder** that no plugin can correct.
  Keep it at `1` unless you have measured your setup.
- `terminal_padding` absorbs a **systematic, whole-cell** offset. Raising
  `draw_inset` to paper over one of these just wastes space and still looks off.
- `cell_aspect` is a **shape**, not an offset. A wrong value shows up as a
  letterbox strip along one edge that no amount of nudging removes.

`:Image calibrate` measures `terminal_padding` and `cell_aspect` together, in
one window, and offers to store them under `stdpath("data")` — per machine,
never in your synced spec, because the right values depend on the terminal and
font size of the machine you are sitting at. Precedence is
defaults < calibration < explicit `setup()` option, checked independently for
each of the two.

### display.remote

| Key | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Allow `:Image show <url>` and hovering an `http(s)` link to download. Off by default on purpose: opening a document should not make an outbound request on its own — the same posture email clients take |
| `timeout_ms` | `10000` | Download timeout |
| `max_bytes` | `20 * 1024 * 1024` | Largest download accepted |

Downloads are cached by URL under `stdpath("cache")/images.nvim/remote`. Only
the single-image path resolves remote targets; `:Image gallery`, `compare`,
`pickers` and `zen` do not.

### display.screenshot

Windows only — the one platform where `:Image screenshot` polls the clipboard
instead of waiting on a file, because the Snipping Tool has no documented way
to write one.

| Key | Default | What it does |
| --- | --- | --- |
| `windows_timeout_ms` | `60000` | How long to wait for a new clipboard image |
| `windows_poll_interval_ms` | `600` | Interval between two clipboard checks |

### display.redact

| Key | Default | What it does |
| --- | --- | --- |
| `padding_cells` | `1` | Safety margin in cells added around every marked box before it is burned in. Over-redacting is the safe failure mode, under-redacting is not |

### display.ascii_fallback

| Key | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Draw coloured block graphics when the terminal check fails, instead of a silently ineffective OSC 1337 sequence. Needs ImageMagick. `false` restores the older silent-no-op-with-a-warning behaviour |
| `levels` | `8` | Steps per colour channel. **Not a quality knob.** Every distinct colour *pair* becomes a highlight group; Neovim stops at 19 602 of them (measured 2026-09-08) and never frees one. Measured worst case — 24 frames of pure noise at 60x24 cells — is 811 groups at this setting, and a hard budget collapses the palette rather than reaching the ceiling |
| `cells` | `"sextant"` | How finely a cell is divided: `"sextant"` (2x3), `"quadrant"` (2x2) or `"half"` (1x2, what this drew before 2026-09-08). **This is the sharpness knob** — see below |

All three live in `images.blocks`, which is also what draws a frame sequence —
the sampling (one ImageMagick process for however many images) and the
painting are shared with it.

### What a finer cell buys, and what it cannot

A cell carries exactly **two** colours whatever character is in it. That is a
property of a terminal, not of the drawing, and no geometry changes it. What a
finer one buys is *shape*: a half block can only say "top" and "bottom", so a
diagonal edge inside a cell is lost; a sextant divides the same cell into six
and the edge survives, even though the two colours do not change.

Measured on one 113x32-cell frame, counting cells that hold any detail at all:

| Geometry | Sub-pixels | Picture | Cells with detail |
| --- | --- | --- | --- |
| `half` | 1x2 | 113x64 | 1 209 |
| `quadrant` | 2x2 | 226x64 | 2 108 |
| `sextant` | 2x3 | 226x96 | 2 328 |

Finding two colours among six sub-pixels means clustering them, which sounds
expensive and is not: **5.9 ms for a whole 24-frame window** in LuaJIT, against
a paint that costs 8 ms per frame either way.

### Why the groups are created before anything is painted

`nvim_set_hl` marks the **whole screen** invalid — Neovim cannot know which
windows a redefined group appears in, so it redraws everything. Creating groups
lazily from inside a paint therefore costs one full screen redraw per new
colour pair, and a frame of real footage introduces plenty: measured over eight
seconds at 113x32 cells, **10 to 476 new pairs per second**, never settling,
because every rolled window brings new material.

Headless that is invisible — nothing redraws, and the paint measures 8 ms. In a
terminal it was reported as **1-2 frames per second**, which is what dozens of
full redraws per frame look like.

So `blocks.prepare(raw, cols, rows)` walks a whole payload and creates every
group it will need, and callers run it once per decoded window — at the
sampling, which already happens a second ahead of when the frames are needed.
The invalidations then collapse into the one redraw that window was going to
cause anyway, and no painted frame creates a group at all. The spec asserts
exactly that: after `prepare`, painting every frame adds zero groups. `octant` (2x4, Unicode 16) is
deliberately not offered — it measured only marginally better than sextants
(2 421 detailed cells) and a terminal without it draws 256 replacement boxes.

Sextants are Unicode 13 (2020), from the "Symbols for Legacy Computing" block.
WezTerm, Kitty, foot and Windows Terminal draw that block themselves rather
than looking it up in a font, so they always have it; a terminal that falls
through to the font may not. **`:checkhealth images` prints a row of each
geometry** — solid shapes mean it renders, replacement boxes mean it does not,
and `"quadrant"` (Unicode 1.1, present everywhere) is the answer that always
draws while still doubling the horizontal resolution of a half block.

With `half`, the cell character is `▀` and the buffer text never changes
between frames — only highlights do. A finer geometry has to choose a
character per cell, so it rewrites the line as well; measured at the same 8 ms,
because the cost was never in writing text.

## paste

| Key | Default | What it does |
| --- | --- | --- |
| `dir` | `"assets"` | Target directory relative to the document. `""` writes next to it |
| `existing_dir_names` | `{ "Resources", "Ressourcen" }` | If the document's directory already holds a folder with one of these names (case-insensitive), that one is used instead of creating `dir` alongside it. `{}` disables the detection |
| `name_template` | `"%s-%d.png"` | `%s` = document stem, `%d` = timestamp |
| `link_template` | `"![](%s)"` | Inserted text without alt text; `%s` = relative path |
| `ask_alt_text` | `false` | `true` prompts for alt text first, producing `![alt](path)`. Cancelling still inserts the plain link — the file is already on disk by then, and a lost link would be the worse surprise |
| `alt_link_template` | `"![%s](%s)"` | Inserted text with alt text; `%s %s` = alt text, relative path |
| `ask_filename` | `false` | `true` prompts for a name, prefilled with what `name_template` would produce. Any path component is dropped and the extension is forced to `.png`. Cancelling here writes nothing at all — unlike the alt-text prompt, the clipboard has not been read yet |

`:Image paste {name}` sanitizes `{name}` the same way and skips the prompt
outright: a name on the command line always outranks `ask_filename`. So does a
count on the keymap, in the other direction — `1<leader>iv` forces the prompt
even with `ask_filename = false`.

## ocr

| Key | Default | What it does |
| --- | --- | --- |
| `lang` | `"eng"` | Passed to tesseract's `-l`. Further languages are a separate download per language; several at once as tesseract writes them, `"deu+eng"` |
| `args` | `{}` | Extra tesseract arguments, appended verbatim — e.g. `{ "--psm", "6" }` for a screenshot that is one uniform block of text rather than a page layout |
| `bin` | `nil` | Absolute path to the tesseract binary. `nil` looks on PATH, then in the usual Windows install directories |

`:checkhealth images` lists which language data is actually installed, and
which of the three lookup routes found the binary.

## pdf

A PDF page drawn as a picture, wherever a host asks this plugin to draw one
(today: `images.integrations.picker`). Needs
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) plus poppler's
`pdftoppm`; with either missing, a PDF is simply not claimed and the host keeps
its own preview.

| Key | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | `false` says "not ours" on a machine that has both pieces |
| `page` | `1` | Which page. There is no paging in a preview window |
| `dpi` | `120` | Rasterization resolution; ~1000x1400 px for A4. Raise it for a large preview window |

Pages are cached under `stdpath("cache")/images.nvim/pdf`, keyed by path,
mtime, page and dpi.

## menu

| Key | Default | What it does |
| --- | --- | --- |
| `enable` | `true` | Whether `images.integrations.menu` returns any entries at all. It contributes right-click entries in the shape [nvzone/menu](https://github.com/nvzone/menu) expects; without that plugin installed it is inert either way |

## keymaps

Registered per buffer, for the filetypes in `keymaps.filetypes`. Every entry
accepts `false` to disable that single mapping.

| Key | Default | What it does |
| --- | --- | --- |
| `show` | `"<leader>im"` | Image under the cursor |
| `gallery` | `"<leader>ig"` | Every image of the buffer, side by side |
| `next` / `prev` | `"<leader>in"` / `"<leader>ip"` | Step through the buffer's images; a count multiplies the step |
| `paste` | `"<leader>iv"` | Paste from the clipboard; **any count** forces the filename prompt |
| `screenshot` | `"<leader>is"` | Take a screenshot; **any count** forces the filename prompt |
| `double_click` | `true` | `<2-LeftMouse>` on a markdown link shows the image. Only set when the buffer has no buffer-local mapping for it already |
| `filetypes` | `markdown`, `vimwiki`, `norg`, `text` | Where all of the above are installed |

The full behaviour of each key — counts, the double-click hand-off to
markdown.nvim, the which-key group — is in
[BINDINGS.md](BINDINGS.md#keymaps).

## Statusline

Not an option, but the other thing `setup()` hands you:

```lua
{ require("images").statusline }  -- "" when nothing is shown, else an icon
```

`statusline(opts)` accepts `{ icon = "…", pinned_suffix = "…" }`.
