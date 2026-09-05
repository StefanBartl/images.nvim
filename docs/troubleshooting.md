# Troubleshooting

Symptoms that have a cause rather than a bug behind them, and which tool
answers which question. Start with `:checkhealth images` — it reports the
terminal, the clipboard tool, the screenshot tool and every declared
dependency in one place.

Three probes, three different questions:

| | Answers |
| --- | --- |
| `:checkhealth images` | is everything this plugin needs present |
| `:Image check` | is OSC 1337 actually getting through to *this* terminal |
| `:Image debug <mode>` | where did that draw go, and why is it not where it was asked to be |

## Nothing is drawn at all

Verify the terminal itself first, outside Neovim:

```sh
wezterm imgcat picture.png
```

If that shows nothing, the terminal does not implement OSC 1337. With
ImageMagick installed, `:Image show`/hover already fall back to a
block-character rendering (`display.ascii_fallback`); without it, this plugin
cannot help. If `imgcat` works but Neovim draws nothing, run
`:checkhealth images`.

A multiplexer is the other common cause — tmux needs
`set -g allow-passthrough on`.

## A coloured block grid appears instead of the real image

That is the ASCII fallback, not a bug: the terminal was not detected as
OSC-1337-capable. `:Image check` confirms the detection. If the terminal *does*
work (`wezterm imgcat` draws) and is only misdetected, set
`display.assume_supported = true` rather than fighting the heuristic — the
protocol has no capability query, so detection is a best guess from environment
variables. See
[architecture.md](architecture.md#detection-is-a-heuristic-and-stays-one).

## The image appears below the statusline

That is what happens when the cursor-positioning sequence does not reach the
terminal — check for a multiplexer, as above.

## The image spills past its frame, or sits a fraction off

Not a drawing problem, a placement one: OSC 1337 addresses whole cells and has
no pixel offset, and neither the cell size nor the terminal's window padding is
readable from inside Neovim. The full derivation is in
[architecture.md](architecture.md#placement-is-whole-cell-and-that-is-the-protocol).

- A **sub-cell** offset is covered by `display.draw_inset` (default `1`), which
  is why images are drawn with a cell of margin rather than flush.
- A **systematic, whole-cell** offset belongs in `display.terminal_padding`.
  Raising the margin to paper over one wastes space and still looks off.
- A **letterbox strip along one edge that no nudging removes** is neither: it
  is a wrong `display.cell_aspect`, a shape rather than an offset.

`:Image calibrate` measures the last two together, interactively, and stores
them per machine. Run it once per terminal setup, not per project — and again
on a different machine, even one running the same synced config.

If the remaining offset is smaller than one cell, calibration says so plainly
rather than pretending to fix it. That part is the protocol limit, and
`display.draw_inset` is what covers it.

## An image lands somewhere unexpected and calibration did not help

`:Image debug` measures instead of guessing:

- `report` — the coordinates actually sent, per draw.
- `columns` — tells a **constant** offset (which `terminal_padding` absorbs)
  from a **scaling** one (which it does not).
- `float` — whether a window is where Neovim claims it is.

## A window opens but stays empty, or shows only its first rows

`nvim_ui_send()` writes to the terminal at once, while Neovim's own repaint
waits for the main loop; a window opened and drawn into in the same tick gets
painted over its own image. Every window-opening path (`zen`, the hover float,
`redact`) defers its draw by one tick for that reason, and
`images.terminal.draw()` flushes pending repaints before sending.

A caller of `images.draw()` that opens its own window has to do the same —
pass `opts.defer = true`. If an empty window still appears from a built-in
path, the terminal is most likely ignoring the sequence entirely; check
`wezterm imgcat` above.

## The image leaves empty space at one edge of the zen window

`preserveAspectRatio=1` scales an image **down** to the sent cell box but never
grows the box to match, so a window wider or taller than the scaled image just
shows nothing in the remainder. `:Image zen` sizes its window to the image's
own aspect ratio for exactly this reason. Without a readable pixel size the
window falls back to the plain `display.zen` fraction.

## The image does not disappear

`:Image clear` forces a repaint. If it comes back on its own, an event is
missing from `display.clear_events` for your workflow. If it *never* clears,
check whether `:Image pin` is active.

## `:Image paste` says there is no image in the clipboard

A copied **file** is not an image on the clipboard — the clipboard has to hold
bitmap data, as it does after a screenshot. On Windows the helper runs
`powershell.exe -STA`; the STA thread is required or the clipboard API always
returns null. On macOS `:Image paste` needs `pngpaste`, on Linux `wl-paste` or
`xclip`.

## `:Image screenshot` times out on Windows

There is no documented way to make the modern Snipping Tool write directly to a
file, so this plugin waits for a new image to appear on the clipboard after
launching it — the least certain of the three platforms. Raise
`display.screenshot.windows_timeout_ms` if you just need more time to make the
selection; `:Image paste` (manual screenshot, then paste) is the unchanged
two-step fallback.

## `:Image screenshot` does nothing on Linux

Needs `grim`+`slurp` (Wayland) or `maim` (X11). `:checkhealth images` reports
which, if either, was found.

## An `.svg` reports that `magick` was not found

Install ImageMagick and make sure `magick` is on PATH. The terminal cannot
decode SVG itself, so there is no fallback for this one format — see
[architecture.md](architecture.md#where-imagemagick-is-a-requirement-rather-than-an-improvement)
for where else that applies.

## `:Image ocr` says tesseract is missing, but it is installed

On Windows the UB-Mannheim installer leaves its "Add to PATH" checkbox
unticked, so a fresh install routinely looks exactly like no install at all.
images.nvim probes `C:/Program Files/Tesseract-OCR/` (and the x86 variant)
anyway; `ocr.bin` overrides both. `:checkhealth images` prints which of the
three routes found the binary.

A different failure looks similar: tesseract is found but has no language data
for what `ocr.lang` asks for. That installs separately, per language
(`tesseract-ocr-deu` and friends), and `:checkhealth images` lists what is
actually there.

## A URL says remote images are disabled

Expected. `display.remote.enabled` defaults to `false` on purpose: opening a
document should not make an outbound request on its own. Set it to `true` to
allow the download.

## `:Image gallery` / `compare` silently skip a remote link

Expected for now — only the single-image `show`/hover path resolves remote
images. A link with a URL target is treated like any other unresolvable link by
the scanning commands, so a gallery can legitimately look sparser than the
buffer's link count.

## A PDF entry in another plugin's picker previews as bytes

Three states look the same from outside, and `:checkhealth images` separates
them: `pdf.enabled = false`, [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)
missing, or poppler's `pdftoppm` missing. With any of the three, a PDF is
simply not claimed and the host keeps its own preview — see
[FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md#pickersnvim-image-and-pdf-previews).
