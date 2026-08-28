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
the draw box. Five distinct failure modes appeared in the process. Four could
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

### 4. The image sits beside its own frame, by the width of a sidebar

**Finding.** With a file tree open on the **left**, a hover drew the image far
to the right of its float — and, far enough right, shrunk to a sliver in the
corner. With the file tree on the right, or with none, the same hover was
correct, and `:Image calibrate` was correct in every case.

A probe on the coordinates actually computed showed the arithmetic to be exact
every time, which is what made this take so long: the numbers sent matched the
window's reported geometry perfectly. The reported geometry was the problem.
On a 170-column screen:

| reported col | content + border | fits? | drawn at |
| --- | --- | --- | --- |
| 141 | 80 + 2 | 141 + 82 = 223 > 170, no | **88** = 170 − 82 |
| 83 | 80 + 2 | yes | 83 |
| 34 | 102 + 2 | yes | 34 |

A floating window that would overhang the screen edge is moved back inside by
Neovim. **`nvim_win_get_position` keeps reporting the requested position**, and
so does `screenpos()` — neither returns where the window landed. Drawing
against the reported value puts the image beside its frame by exactly the
overhang, and `clamp_to_screen` then shrinks the box to whatever is left of the
screen, which is where the sliver came from.

Why only a file tree on the *left*: it pushes the cursor right, so a
cursor-relative hover float overhangs and gets moved. On the right the cursor
stays at low columns and nothing moves. `:Image calibrate` is
`relative = "editor"` and centred, so it never overhangs — which is why the
one deliberately controlled test kept coming out clean while the real feature
did not.

**Rule.** Never draw against a float's reported position without checking that
it fits. Implemented in `images.anchor.placed_position`.

### 5. The image sits a fraction of a cell off (not solvable)

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
contain the overhang means the offset is not a pure sub-cell effect but
predominantly a whole-cell shift.

**Measured afterwards, on that same setup:** `terminal_padding = { row = -2,
col = 0 }` with `draw_inset = 1` places both files correctly. So the shift is
exactly two cells downward — the earlier inference that it must be *more* than
two was wrong, and wrong for an instructive reason: the one-cell margin the
reserve was measured against sits on *both* edges, so a 2-cell correction and a
1-cell margin do not add up to a 3-cell budget at the bottom. A reserve is not a
correction, and reading one as evidence about the other is how this measurement
went astray twice.

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

### 6. The image is letterboxed inside its own frame

**Finding.** A hovered image sat ~2.7 cells right of its frame's left edge,
with matching slack on the right. It looked like a placement error and was
chased as one; it is not one at all.

The float is sized to fit the image — `fit_cells` returned 77x20 for a
1200x675 picture, ratio 1.771 against the image's 1.778. `images.anchor`
then keeps `draw_inset` cells free on **every** side and hands the terminal
75x18, ratio **1.917**. Two cells off 20 rows is a larger relative change
than two off 77 columns, so the box's shape moves, and
`preserveAspectRatio=1` does exactly what it promises: fits the image and
centres the remainder.

**Rule.** Fit the image to the box it will actually be drawn in, then add
the inset back for the frame. Implemented in `lib.nvim.hover.preview.media`'s
`canvas_cells`. Any other consumer sizing a window to an image must do the
same, or `draw_inset` will letterbox it.

### 7. The image sits beside its frame by the width of a sidebar

**Finding.** With a file tree open on the left, a hovered image landed ~26
columns right of its frame — the tree's exact width — and overhung it.
Without a tree it was correct. Superficially failure mode 4, but **not** the
same cause: no float overhung the screen, so `placed_position` never
engaged.

**`nvim_win_get_position` reports a wrong column for a `relative = "cursor"`
float when the editor window does not start at column 0.** It adds the
window's origin to a cursor position that already contains it. Measured with
a 26-column tree: a float whose frame is drawn at column ~59 reports **83**.
Neovim draws it correctly; only the number handed back is wrong.

That is fatal wherever a float's geometry *is* the drawing box: the offset
computed from it is correct, the origin is not, and the picture lands beside
its own frame.

**Rule.** Do not open a float `relative = "cursor"` when its geometry will be
read back. Take the cursor's true grid position from `screenpos()` and open
`relative = "editor"`, which reports back exactly what it was given.
Implemented in `lib.nvim.hover.float`.

### Ruled out while hunting modes 6 and 7 — do not re-check these first

Each of the following was measured, produced a clean result, and cost a
round. Recorded so the next investigation starts further along:

| Suspected | Verdict |
| --- | --- |
| `window_padding` (mode 5) | Set to `0`, WezTerm fully restarted — screen grew 170x37 → 172x39, confirming it took effect. **The offset survived.** It contributed to mode 6's slack but caused neither bug. |
| Wrong `cell_aspect` | `:Image calibrate`'s card filled its frame exactly at 0.46. A wrong aspect letterboxes; it does not displace. |
| Overhanging float (mode 4) | `placed_position` verified still correct when engaged (col 130 of 170, extent 82 → sent 91). But **no float overhung** in any measurement, so it never engaged. |
| `images.terminal.draw` | Drew the same card at columns 8/51/94/137 with and without a file tree: identical pixel positions every time. Correct at any screen column. |
| Deferred measurement | The float's reported position is identical at `open` time and one tick later at draw time. Not a timing window. |
| A stale image from a previous hover | An explicit `clear()` changes nothing, and the offset neither travels with the cursor nor produces a second picture. |
| Proportional / scale error | `columns` mode: no growth left-to-right. The error was constant, then turned out to be two separate constant errors. |

### How to measure any of this: `:Image debug`

The five failure modes above were each found by measurement, and the
measurements are now part of the plugin rather than scratch scripts:

| Command | Answers |
| --- | --- |
| `:Image debug report` | What coordinates go to the terminal, per draw, against an independently recomputed expectation. Run once to arm, again to print. |
| `:Image debug columns` | Draw the same card at four columns. A displacement growing left-to-right is a scale error; a constant one is an offset `terminal_padding` can absorb. |
| `:Image debug float [path]` | Open a float, draw into it, and mark the float's **reported** corner. Marker off the corner ⇒ failure mode 7. |

**Two traps worth knowing before trusting a result.**

First: a `delta` of `0/0` in `report` proves only that the sent coordinates
match the *reported* float position. Both bugs above produced `0/0`
throughout, because everything downstream of the origin was correct. Only
`float`'s marker compares the report against reality.

Second, and the reason failure mode 6 hid for so long: **`images.testcard`
builds its card to whatever box it is handed.** A generated card fills any
frame by construction and can never reveal an aspect-ratio problem. Pass a
real image to `columns`/`float` — and note that a probe passing `inset = 0`
is also bypassing mode 6 by definition.

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
