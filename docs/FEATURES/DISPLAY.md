# Display

Everything involved in actually drawing an image, or deciding it can't be
drawn and falling back gracefully.

## Show the image under the cursor

Resolves the markdown/plain-text link under the cursor (or an explicit
path/URL) and draws it via the iTerm2 OSC 1337 protocol.

- **Module:** `images/init.lua` (`M.show`), `images/resolve.lua`
  (`M.under_cursor`, `M.to_path`), `images/terminal.lua` (`M.draw`)
- **Usercmds:** `:Image`, `:Image show [path]` ([usercmds](../BINDINGS.md#user-commands))
- **Keymaps:** `<leader>im` ([keymaps](../BINDINGS.md#keymaps))

## Hover overlay / hover float

Shows the image whenever the cursor sits on a link, without an explicit
command. `display.hover_mode = "overlay"` (default) draws straight over
the text and clears on the next cursor move; `"float"` shows the same
image in a small, unfocused floating window under the cursor instead —
same lifecycle, same draw call, different container. Only the single-image
path is affected; the gallery keeps its own layout either way.

- **Module:** `images/init.lua` (`M.hover`), `images/hover_float.lua`
- **Config:** `opts.display.hover_mode` (default `"overlay"`),
  `opts.display.clear_events`

## Pin

Keeps the currently shown image on screen instead of clearing it on the
next `clear_events` trigger (cursor move, insert mode, buffer leave,
window scroll).

- **Module:** `images/init.lua` (`M.pin`)
- **Usercmds:** `:Image pin` ([usercmds](../BINDINGS.md#user-commands))

## Terminal capability detection

Before the first draw, the terminal is checked against the small set that
implements OSC 1337 (WezTerm, iTerm2, Konsole), detected from environment
variables. An unknown terminal produces a warning once per session and
still attempts the draw — there is no capability query for this protocol,
so this is a heuristic and a false negative must not break a working
setup.

- **Module:** `images/terminal.lua` (`M.capability`,
  `M.reset_capability`), `images/guard.lua` (`M.check`, `M.reset`)
- **Usercmds:** `:Image check` ([usercmds](../BINDINGS.md#user-commands))
- **Config:** `opts.display.assume_supported` (default `false`, silences
  the warning without changing draw behavior)

## ASCII / block-character fallback

When the terminal check fails, `:Image show`/hover draw a colored
block-character (`█`) rendering instead of a silently ineffective OSC 1337
sequence — a true-color foreground sampled per terminal cell straight from
the image, the same technique `chafa`/`viu` use, rather than a brightness
character ramp. Requires ImageMagick to read pixel data. Only the
single-image path gets this fallback.

- **Module:** `images/ascii.lua` (`M.open`, `M.available`)
- **Config:** `opts.display.ascii_fallback.enabled` (default `true`)

## Remote image display

`:Image show <url>` and hovering a markdown link pointing at
`http(s)://…` download and cache the image before drawing. Off by default
— a document merely being opened should not silently trigger a network
request, the same posture email clients take toward remote images.
Downloads are cached by URL with a size and time limit. Gallery, compare,
pickers and zen do not resolve remote images yet — only the single-image
path does.

- **Module:** `images/remote.lua` (`M.is_remote`, `M.fetch`)
- **Config:** `opts.display.remote.enabled` (default `false`),
  `opts.display.remote.timeout_ms`, `opts.display.remote.max_bytes`

## Zen: full-screen single image

Shows one image full-screen in a real, editable window rather than an
overlay — survives a snacks hover popup opened alongside it. Redraws on
`WinResized`/`VimResized` to follow the window's size, clears on
`WinClosed`.

- **Module:** `images/zen.lua` (`M.open`, `M.close`, `M.dimensions`)
- **Usercmds:** `:Image zen [path]` ([usercmds](../BINDINGS.md#user-commands))
- **Config:** `opts.display.zen.width`/`height` (fractions of the editor,
  default `0.9`/`0.85`)

## Positioned draw primitive

Draws an image at a named anchor ("full" or one of nine
corner/edge/center anchors) inside a target window — the reliable,
single-shot primitive that zen, the hover float, redact and the picker
preview all delegate to internally, and that other plugins can call
directly.

- **Tab:** true
- **Module:** `images/anchor.lua` (`M.draw`, `M.resolve_window`),
  `images/scale.lua` (`M.POSITIONS`, `M.anchor_box`)
- **Usercmds:** `:Image draw <position> [path]` ([usercmds](../BINDINGS.md#user-commands))

### Why the timing matters

`nvim_ui_send` writes to the terminal immediately, while Neovim only
repaints once control returns to the main loop. Open a window and draw
into it in the same tick and Neovim paints that window's cells over the
image right after it was sent — the popup is visible, the image is gone
or half gone. `images.terminal.draw` flushes anything already pending
before sending its own payload, and every caller that opens a window
first (zen, hover float, redact) defers its draw by one tick
(`opts.defer = true`) so the flush actually covers the repaint the window
itself causes. `show`/hover need neither, since they draw over existing
text without creating a window. Every consumer of `images.draw()` gets
this handled once, in one place, instead of re-solving the same timing
problem per caller.

## Placement calibration

Measures how this terminal actually places an image, and stores the
correction so every later draw lands where it was asked to.

- **Tab:** true
- **Module:** `images/calibrate.lua` (the interactive part),
  `images/testcard.lua` (generates the card),
  `images/calibration.lua` (persistence)
- **Usercmds:** `:Image calibrate` ([usercmds](../BINDINGS.md#user-commands))
- **Config:** writes `display.terminal_padding` and `display.cell_aspect`;
  the sub-cell remainder is covered by `display.draw_inset`

### Why this is not automatic

Images are positioned with `CSI row;col H`, which addresses whole cells
only — OSC 1337 has no pixel offset. A terminal whose window padding is
not a multiple of the cell size therefore places the image slightly off,
and nothing in Neovim can see that: `:h TermResponse` forwards only DA1,
OSC, DCS and APC responses, and the cell-size reply (`CSI 16 t` →
`CSI 6 ; h ; w t`) is a plain CSI response, so it never arrives.
`nvim_list_uis()` reports cells, not pixels. Neither cell size nor window
padding is knowable from inside the editor.

The offset is not even a constant that could be written into the docs:
during measurement the same file needed one correction at one cursor
position and a different one at another.

### How the tool works

`:Image calibrate` opens a framed window and draws a test card generated
to exactly that box's aspect ratio — generated, not shipped, because the
box depends on `display.cell_aspect` and the window size and so is only
known at runtime.

The card is then nudged into place with `hjkl` or the arrow keys, one
cell per press, redrawn immediately. `r` resets, `<CR>` accepts, `q`
cancels. Nobody has to estimate how far off it is — the answer is
"push until it sits", which is the same information without the detour
through a number that cannot be read off a screen.

`+`/`-` nudge `display.cell_aspect` itself, in 0.01 steps, rebuilding the
card on every press. This is what tells a wrong aspect apart from a
placement error: a card built with the wrong ratio letterboxes — a strip
along one edge that `hjkl` cannot nudge away, because it is a wrong shape,
not an offset. Both values are measured in the same window because both
are per-machine in exactly the same way (see "Why this is not automatic"
above), and a setup with the wrong one now shows the symptom instead of
looking like a placement bug with no cure.

An earlier version asked about each edge through a select popup instead.
That could not work: the popup is a window, and Neovim paints over the
cells it covers, including the image being judged.

Accepting offers to store the result under `stdpath("data")`, from where
it is merged on every `setup()`. It is deliberately not written into the
user's spec: the right values depend on the terminal and font size of the
machine, so a synced dotfile would carry a wrong value to the next one.
Precedence is defaults < calibration < explicit `setup()` options, checked
independently for `terminal_padding` and `cell_aspect`, and calibration
warns when a hand-written option shadows what was just measured.

If nudging steps over the correct position without ever landing on it,
the remaining offset is smaller than one cell. The window says so in its
footer while it is open, and `display.draw_inset` is what covers that
remainder — the protocol limit, stated rather than hidden.

## Status line segment

Reports whether an image is currently shown, for embedding in a
statusline plugin like lualine.

- **Module:** `images/init.lua` (`M.statusline`)
