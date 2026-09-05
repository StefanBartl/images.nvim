# Architecture — why OSC 1337, and what follows from it

One decision shapes this plugin: it speaks the **iTerm2 inline-image protocol
(OSC 1337)** rather than the **Kitty graphics protocol** every other Neovim
image plugin relies on. Everything below is a consequence of that, including
the four things images.nvim cannot do.

## Table of contents

- [Why not snacks.image or image.nvim](#why-not-snacksimage-or-imagenvim)
- [What it takes to draw reliably](#what-it-takes-to-draw-reliably)
- [Placement is whole-cell, and that is the protocol](#placement-is-whole-cell-and-that-is-the-protocol)
- [Detection is a heuristic, and stays one](#detection-is-a-heuristic-and-stays-one)
- [The four costs, and where each one shows up](#the-four-costs-and-where-each-one-shows-up)

## Why not snacks.image or image.nvim

Both speak only the Kitty graphics protocol. On native Windows Neovim running
in WezTerm, Kitty APC sequences (`ESC _G`) are never drawn when they come from
Neovim — the very same sequences work from a raw shell, so the difference is
introduced by Neovim's output layer, not by the terminal. That makes both
plugins unusable there regardless of configuration, and no amount of
configuration is the point: it is the wrong protocol for that combination.

There is a second, independent reason on the same platform.
`snacks.image` needs the pixel size of a terminal cell to size its output, and
gets it from `ioctl(TIOCGWINSZ)` — a call that cannot work on native Windows.
OSC 1337 takes `width` and `height` **in cells** together with
`preserveAspectRatio=1`, so the terminal does the scaling and the pixel size of
a cell never has to be known at all.

## What it takes to draw reliably

Four details, all of them learned the hard way, none of them obvious from the
protocol specification:

- **Output goes through `vim.api.nvim_ui_send`, not `io.stdout:write`.** The
  latter draws exactly once per terminal session and then silently stops.
- **The cursor is saved and positioned first** — `ESC[s` /
  `ESC[<row>;<col>H` / payload / `ESC[u`. Without that the image lands below
  the statusline and pushes it up.
- **Positioning and payload go out in one `nvim_ui_send`.** Neovim's own TUI
  renderer writes to the same tty stream and may flush cursor movements of its
  own between two calls. If that happens after the positioning, the image is
  drawn wherever Neovim's cursor happens to sit — the same result as no
  positioning at all, only sporadic rather than consistent, and therefore far
  harder to attribute.
- **Drawing is ordered against Neovim's own repaint, in two places.**
  `nvim_ui_send` writes to the terminal immediately, while Neovim only paints
  once control returns to the main loop. Open a window and draw into it in the
  same tick and Neovim paints that window's cells over the image right after it
  was sent — popup visible, image gone or half gone. So `images.terminal.draw`
  flushes anything already pending before its payload goes out, **and** every
  path that opens a window first (`zen`, `hover_float`, `redact`) defers its
  draw by one tick. A flush before sending cannot cover the repaint that
  opening the window itself causes. `show`/hover need neither: they draw over
  existing text without creating a window.

Every caller gets this handled once, in `images.anchor.draw` — which is why
[`images.draw()`](FEATURES/DISPLAY.md#positioned-draw-primitive) is the entry
point another plugin should reach for rather than re-solving the timing
problem per call site.

### The box sent is shaped like the picture, not like the window

`preserveAspectRatio=1` scales the image down to the sent cell box on the axis
that binds **first** — and only that one. Send a box wider than the picture's
ratio can use and the terminal fits the width, letting the height follow:
measured in WezTerm, a 993x1404 PDF page in an 82x25 preview window came out
57 rows tall, ran off the bottom of a 40-row screen, and scrolled Neovim's
whole grid up with it.

So every draw fits the box to the picture first
(`images.scale.fit_cells`), which makes both axes right and the placement this
plugin's decision rather than the terminal's. The dimensions come from the
file's own header (`images.pixels` — PNG, JPEG, GIF, BMP, WebP), so this holds
without ImageMagick. A file that states no pixel size (SVG, an unknown
container) falls back to the plain window box, which is the older,
terminal-dependent behaviour. `:Image zen` and `:Image redact` shape their
*window* that way up front too, so a frame never has an empty strip in it.

## Placement is whole-cell, and that is the protocol

Images are positioned with `CSI row;col H`, which addresses **whole terminal
cells only** — OSC 1337 has no pixel offset. A terminal whose window padding is
not a multiple of the cell size therefore places the image a fraction of a cell
off, and a plugin cannot correct for it, because neither number is knowable
from inside Neovim:

- `:h TermResponse` forwards only DA1, OSC, DCS and APC responses. The
  cell-size reply (`CSI 16 t` → `CSI 6 ; h ; w t`) is a plain CSI response, so
  it never arrives.
- `nvim_list_uis()` reports cells, not pixels.

This is measured, not assumed. The offset is not even a constant that could be
written into documentation: during measurement the same file wanted `-2` at one
cursor position and `-3` at another, with `-2` already overshooting at a third.

Two mechanisms follow, and they cover different things:

| | Absorbs | Default |
| --- | --- | --- |
| `display.draw_inset` | the **sub-cell remainder** — an offset smaller than one cell stays inside the frame instead of visibly spilling over it | `1` cell, centred |
| `display.terminal_padding` | a **systematic, whole-cell** offset | `{ 0, 0 }` |

Raising the margin to paper over a systematic offset wastes space and still
looks off. Conversely, a wrong `display.cell_aspect` is neither: it is a wrong
*shape*, and shows up as a letterbox strip along one edge that no nudging
removes.

`:Image calibrate` measures `terminal_padding` and `cell_aspect` together
rather than asking you to work them out — see
[FEATURES/DISPLAY.md](FEATURES/DISPLAY.md#placement-calibration) for how the
tool works, and [configuration.md](configuration.md#placement-draw_inset-terminal_padding-cell_aspect)
for the three options as options. When an image still lands somewhere it should
not, `:Image debug` measures instead of guessing; the failure modes its three
modes were built to distinguish turned up two real bugs.

## Detection is a heuristic, and stays one

OSC 1337 has **no capability query**. Before the first draw the terminal is
checked against the small set known to implement it (WezTerm, iTerm2, Konsole),
detected from environment variables. An unknown terminal produces a warning
**once per session** and the image is still drawn — a false negative must not
break a working setup. `display.assume_supported = true` silences the warning;
`:Image check` re-runs the detection.

There is exactly one place where a failed check means *no*:
`images.integrations.picker.available()`. Taking a foreign preview window over
and then drawing nothing leaves an empty window where the host's own text
preview would have worked, so that inversion is deliberate.

### And there are no image IDs either

Nothing that has been drawn can be removed individually — only the whole screen
can be repainted. `images.terminal` therefore keeps a single "something is
showing" flag rather than a placement registry, `:Image clear` repaints via
`:mode`, and every windowed draw arms a one-shot `WinClosed` for its own
window. A host that draws into its own preview window calls
`images.integrations.picker.clear()` when the selection moves from an image to
a non-image entry, because there the window stays open.

## The four costs, and where each one shows up

Four apparent limitations are one cause. Reading them separately makes each
look like a missing feature; together they are the price of the protocol that
draws at all on this platform.

| Cost | Why | Where |
| --- | --- | --- |
| **No images inline in the text flow** | Inline placement needs Unicode placeholders, which only Kitty and Ghostty implement — and neither ships for Windows | `display.hover_mode = "overlay"` draws *over* the text and clears on the next cursor move; `"float"` puts the same image in a small window instead |
| **Placement is whole-cell** | `CSI row;col H` has no pixel offset, and neither cell size nor window padding is readable from Neovim | `display.draw_inset`, `display.terminal_padding`, `:Image calibrate` |
| **SVG needs ImageMagick** | WezTerm decodes PNG/JPEG/GIF/WebP/BMP itself but not SVG; an `.svg` is rasterized to a cached PNG first, and without ImageMagick opening one reports a clear error rather than failing silently | `extensions`, `images.convert` |
| **Terminal support is guessed** | the protocol has no capability query | `display.assume_supported`, `:Image check`, and the block-graphics fallback in `display.ascii_fallback` |

### Where ImageMagick is a requirement rather than an improvement

Two of the four costs above are the reason it is needed at all, and the rest
follow from what the operations themselves are. The full list, so that no page
has to keep a count:

| Needs ImageMagick | Because |
| --- | --- |
| SVG display | the terminal cannot decode it; it is rasterized to a cached PNG first |
| the block-graphics fallback | reading pixel colours out of an arbitrary raster file needs a real decoder, which plain Lua does not have |
| `:Image redact` | the boxes are burned in by an image operation |
| `:Image scale` / `optimise` / `convert` | they *are* image operations end to end — an image operation without an image library is not a degraded feature, it is no feature |
| `:Image export` | **unless** [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) is installed, in which case it routes through that instead |

Everywhere else ImageMagick only unlocks detail — `:Image info`'s dimensions,
`:Image compare`'s relative scaling — and its absence degrades the result
rather than removing the command. See
[installation.md](installation.md#optional-external-tools).
