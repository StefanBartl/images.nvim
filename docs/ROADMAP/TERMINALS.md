# TERMINALS — protocols, backends, detection

## Starting point

The finding this plugin rests on, in short:

| Environment | Kitty APC (`ESC _G`) | iTerm2 OSC 1337 |
| --- | --- | --- |
| pwsh in WezTerm/Windows | works | works |
| **nvim** in WezTerm/Windows | **never drawn** | works |

ConPTY is not the cause — both protocols cross the pipe intact, demonstrably so
with `wezterm imgcat`. The difference is introduced by Neovim's output layer.
Since `snacks.image` and `image.nvim` both send Kitty APC exclusively, they are
unusable there.

Two pitfalls when measuring, both of which cost time:

- OSC images persist. Two test phases at the **same** position lead to a
  leftover image being read as the second phase's success. Always use different
  positions.
- Terminal state matters. For reliable measurements restart WezTerm completely,
  not merely open a new tab.

## Placement: what was measured, and what follows from it

A hover float draws the image into a window whose geometry is simultaneously
the draw box. Four distinct failure modes appeared in the process. Three could
be fixed; one is a limit of the protocol. The measurements come from WezTerm
`20240203-110809` on Windows 11, Neovim 0.12.2, JetBrainsMono Nerd Font 12pt —
the derived rules hold generally, the concrete numbers only for this setup.

### 1. The image sits in the wrong place, the status line rides up

**Finding.** The four parts of the sequence (`ESC[s`, positioning, payload,
`ESC[u`) went out as four separate `nvim_ui_send` calls. Neovim's own TUI
renderer writes to the same tty stream and may flush in between; when that
happens between positioning and payload, the image lands wherever Neovim's
cursor currently is.

**Rule.** The complete sequence must go out in **one** `nvim_ui_send`.
Implemented in `images.terminal.sequence_for`.

### 2. The terminal scrolls, and Neovim's grid travels with it

**Finding.** OSC 1337 with `inline=1` advances the cursor down by the image's
height. If the image ends on the last row, that single step scrolls the whole
screen — Neovim's grid included, without Neovim finding out. `ESC[u` restores
the cursor position afterwards but not the scroll.

**Rule.** Clip the draw box to the screen, with **one row of safety margin**
for the cursor advance. Implemented in `images.terminal.clamp_to_screen`.

### 3. The image overlaps the window border

**Finding.** `nvim_win_get_position` returns the **same** value for a bordered
and an unbordered window with identical configuration — the border's outer
edge, not the start of the content. Verified against `screenpos()` with a UI
attached:

| Border | `screenpos(1,1)` relative to `pos + 1` |
| --- | --- |
| `none` | +0 rows / +0 columns |
| `rounded`, `single` | **+1 / +1** |
| top only | +1 / +0 |
| left only | +0 / +1 |

`nvim_win_get_width`/`_height` are **not** affected: they always report the
content area only.

**Rule.** Indent by one cell per axis as soon as the corresponding border
segment is set. Implemented in `images.anchor.border_inset`.

### 4. The image sits a fraction of a cell off (not solvable)

**Finding.** Isolation tests with a full WezTerm restart between every run:

| `window_padding` | `tab_bar_at_bottom` | Result |
| --- | --- | --- |
| `9/8/8/8` | `true` | image visibly too low, overhanging at the bottom |
| `0/0/0/0` | `true` | **image exactly right** (a remainder on one aspect ratio only) |
| `9/8/8/8` | `false` | vertically right, but clearly off horizontally |

First inference: **`window_padding` is the cause**, not the tab bar position.
Second inference, from the third row: turning `tab_bar_at_bottom` merely trades
one error for another — not a workaround, just a displacement.

**Why part of this cannot be computed away.** `CSI row;col H` positions in
**whole cells** only; OSC 1337 has no pixel offset. Padding that is not an even
multiple of the cell size (here: 9 px on the left against a cell roughly 10 px
wide) produces a sub-cell offset no row/column value can resolve — however
precisely the padding is known.

**But the offset is not only sub-cell.** A later measurement with a probe
directly on `images.terminal.draw` (the coordinates actually sent, not the
model) at `window_padding = "1cell"` all round and `tab_bar_at_bottom = true`:

| File | sent | reserve at the bottom | Observation |
| --- | --- | --- | --- |
| `pdf_inline_hover.png` | `row=16 col=45 cols=78 rows=16` | 2 cells (44 px) | a gap at the top, and **still** an overhang at the bottom |
| `image_inline_hover.png` | `row=21 col=45 cols=78 rows=17` | 2 cells (44 px) | likewise |

The values sent match the specification exactly (`80−2`, and `18−2` / `19−2`) —
so the arithmetic is not the cause. That a 44 px reserve at the bottom does not
contain the overhang means the offset is **larger than two cells**, and hence
not a pure sub-cell effect but predominantly a whole-cell shift.

**Rule.** The integer part belongs in `display.terminal_padding` (negative, to
correct upwards), not in the margin. Only what remains below that is the real,
unresolvable protocol limit. The margin is therefore not a substitute for the
compensation but a buffer for it.

**What the plugin makes of this.** Because a plugin can neither measure nor
query the offset, the default is **not** flush drawing but a margin of one cell
all round (`display.draw_inset = 1`). A sub-cell offset then stays *inside* the
frame rather than visibly spilling past it — on every terminal, with no
configuration and no detection.

All round rather than only where the offset goes: a one-sided reserve
(bottom/right, the direction padding pushes content) would cost half as much;
it was built and discarded again. It leaves the image clinging to the left
border with a gap on the right — and the viewer reads that asymmetry as a
defect regardless of what it prevents. A *systematic* offset does not belong in
the margin anyway but in `display.terminal_padding`; the margin only absorbs
the remainder.

**Why this became a tool rather than a line of documentation.** The correction
needed is not constant: the same file wanted `-2` at one cursor position, `-3`
at another, and at a third `-2` was already overshooting. A value written into
the docs would therefore be wrong even for *one* setup, let alone someone
else's installation. Hence `:Image calibrate` (see `images.calibrate`): a
generated test card that fills the draw box exactly, nudged into place with
`hjkl`/arrows one cell at a time. Nobody has to estimate how far off it is —
the answer is "push until it sits". The result is stored per machine under
`stdpath("data")` (`images.calibration`), not in the user's spec.

**For a measured setup, in this order.**

1. Set `window_padding` to **0**. The only entirely clean variant.
2. Otherwise put `window_padding` on an **even multiple of the cell size** — in
   WezTerm via the `cell` unit (`"1cell"`) rather than pixels. Careful: by our
   own measurement `"1cell"` refers to the cell **width**, for `top`/`bottom`
   as well; vertically that is therefore not a multiple of the cell height and
   the offset remains. Vertically use either `0` or a pixel value that is a
   multiple of the cell height.
3. If an integer offset remains after that, compensate it via
   `display.terminal_padding = { row = …, col = … }` and draw flush with
   `display.draw_inset = 0`.

That the very same mechanics appear in other terminals with window chrome of
their own is to be expected; it was only measured in WezTerm.
`display.terminal_padding` is therefore worded terminal-neutrally and defaults
to `{ row = 0, col = 0 }`, a plain no-op.

### What is fundamentally impossible from inside Neovim

For the cell size there is the query `CSI 16 t`, answered with
`CSI 6 ; <height> ; <width> t`. **That answer never reaches a plugin:** `:h
TermResponse` explicitly names only **DA1, OSC, DCS and APC** responses, and
`CSI 6 ; … t` is a plain CSI response. `nvim_list_uis()` likewise reports cell
dimensions only, no pixels — verified with a UI attached.

There is therefore **no** way to determine cell size or window padding
automatically. A first attempt via `CSI 16 t` + `TermResponse` was built, came
to nothing and was removed again; `display.cell_aspect` and
`display.terminal_padding` are deliberately manual values. This is also why the
"no cell measurement" guardrail (see [README](./README.md)) exists: not for
reasons of effort, but because the interface does not allow it.

Explicitly **not** affected is XTVERSION (`ESC [ > q`) from the
[Detection](#detection) section: its answer is DCS and is forwarded.

## Further backends

- **Sixel** for terminals that can do it but not OSC 1337 (xterm with
  `--enable-sixel-graphics`, mlterm, Windows Terminal from 1.22). The
  second-widest reach after OSC 1337.
- **Kitty APC** for Kitty and Ghostty, where it works. There it would also bring
  Unicode placeholders and with them **genuine inline rendering in the text
  flow** — the one thing this plugin fundamentally cannot do today.
- **ASCII art** as a universal fallback, see `color_my_ascii.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
- **The system application** as a last resort. `open.nvim` already does this; in
  the plugin itself it would be the most honest response to a terminal with no
  graphics capability at all.

## Detection

Today `images.health` guesses from `TERM_PROGRAM` and `WEZTERM_*`. A real query
would be better:

- `ESC [ > q` (XTVERSION) returns the terminal name and version via
  `TermResponse`. That route demonstrably works on Windows — `snacks.image`
  detects WezTerm correctly with it, even though it then draws nothing.
- Kitty has a protocol-native query; OSC 1337 does not, so there it would remain
  a list of names.

As long as only one backend exists the effort is not justified: detection would
only determine whether a warning appears. With a second backend it becomes a
prerequisite.

## tmux and SSH

- **tmux** needs `set -g allow-passthrough on`, or it swallows the sequences.
  The health check already warns but does not set it — that would be an
  intrusion into the user's configuration.
- **SSH** works in principle, because the image data travels inline in the
  sequence rather than as a file path. With large images the transfer becomes
  noticeable; downscaling beforehand would be the case where ImageMagick brings
  real benefit.

## Reading and references

- [iTerm2 Inline Images Protocol](https://iterm2.com/documentation-images.html)
  — the OSC 1337 `File=` sequence this plugin sends, including giving
  `width`/`height` in cells and `preserveAspectRatio`.
- [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  — the protocol used by snacks.image and image.nvim, including the Unicode
  placeholders needed for genuine inline rendering.
- [WezTerm — imgcat](https://wezfurlong.org/wezterm/imgcat.html) — which
  protocols WezTerm implements; `wezterm imgcat` is the quickest test of
  whether a terminal can show images at all.
- [Sixel Graphics](https://en.wikipedia.org/wiki/Sixel) — background on the
  oldest of the three protocols and its adoption.
- [Neovim `nvim_ui_send()`](https://neovim.io/doc/user/api.html) — the output
  route this plugin writes through; available from API level 14.
