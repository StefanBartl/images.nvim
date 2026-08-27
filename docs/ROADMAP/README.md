# ROADMAP — images.nvim

A collection of ideas. Nothing here is a commitment, and the order is not a
prioritisation.

| File | Contents |
| --- | --- |
| [CROSS-PLUGIN.md](./CROSS-PLUGIN.md) | Cross-cutting features with the other `*.nvim` repos |
| [TERMINALS.md](./TERMINALS.md) | Protocols, backends, terminal detection |

A third file, `FEATURES.md`, was planned for ideas about the plugin's own
display/editing/clipboard side and never written — the list below took its
place, and the two files above are the whole folder.

## Already implemented

For what the features *do*, see [`docs/FEATURES/`](../FEATURES/); this list is
here so nothing above gets confused with what already exists:

- Display via OSC 1337 with cursor positioning (`:Image`, `:Image show`)
- A gallery of several images on a grid (`:Image gallery [columns]`), including
  over a range (`:'<,'>Image`, `:'<,'>Image gallery`)
- Selection through lib.nvim's UI kit, falling back to `vim.ui.select`
  (`:Image list`)
- Navigation through a buffer's images (`:Image next` / `prev`)
- Metadata via ImageMagick, optional (`:Image info`)
- SVG display through automatic PNG conversion, cached (`images.convert`)
- Remote images for `:Image show`/hover, cached, off by default
  (`display.remote`, `images.remote`) — not gallery/compare/pickers/zen yet
- Clipboard -> file + link (`:Image paste`), optionally with alt-text and file
  name prompts (`paste.ask_alt_text`, `paste.ask_filename`)
- An interactive screenshot instead of the clipboard detour (`:Image
  screenshot`, `images.screenshot`), asynchronous on all three platforms — the
  Windows route (clipboard polling after `ms-screenclip:`) is the least certain
  of the three implementations, see the module docs
- Replace an image, keeping the link (`:Image replace`)
- Export an image as a PDF next to the source file (`:Image export`,
  `images.convert.to_pdf`); requires ImageMagick
- Redaction mode: mark boxes in cells (visual mode + `<CR>`, a real zen-like
  window), black them out and save as a new file; the original stays
  (`:Image redact`, `images.redact`, `images.convert.redact`) — geometry via
  `images.scale.fit_cells`/`cell_box_to_pixels` with a configurable safety
  margin (`display.redact.padding_cells`); requires ImageMagick. Documented in
  [`docs/FEATURES/CAPTURE.md`](../FEATURES/CAPTURE.md) — the `REDACT.md`
  concept note this used to point at was never written; the feature shipped
  first.
- Find orphaned images in `paste.dir` and delete them on confirmation
  (`:Image orphans`)
- A filesystem-wide search with a live preview via `snacks.picker`, a soft
  dependency (`:Image pickers cfile|cwd|path`)
- A comparison mode with genuine relative scaling: when `images.info` knows both
  pixel dimensions (ImageMagick), the smaller image gets a proportionally
  smaller, centred box instead of filling its pane — see `images.scale` and
  `lib.nvim.ui.kit.compare`'s `on_compare` hook, added for exactly this
  (`:Image compare cfile|cwd|path`)
- A large single display in a real, editable window rather than a preview float
  (`:Image zen`)
- A floating window instead of draw-over-text for `:Image show`/hover, opt-in
  (`display.hover_mode = "float"`, `images.hover_float`) — the same
  open-a-window-then-draw technique as `:Image zen`
- Pin the display (`:Image pin`)
- A status line indicator (`require("images").statusline`)
- A which-key group for the `<leader>i` prefix, derived from the configured keys
- Double-clicking a markdown link
- Terminal capability detection with a one-off warning, never a hard refusal
  (`:Image check`, `display.assume_supported`)
- An ASCII fallback for terminals without OSC 1337: coloured block graphics via
  ImageMagick sampling plus extmarks, instead of the ineffective sequence
  (`display.ascii_fallback`, `images.ascii`) — the single-image path only, as
  with remote images. Originally considered as a color_my_ascii.nvim
  integration (see CROSS-PLUGIN.md); but its highlighter colours known character
  classes against a scheme, pattern-based, not arbitrary per-cell pixel RGB —
  the wrong fit for real image colours, hence a dedicated path without the
  dependency.
- Placement calibration (`:Image calibrate`, `images.calibrate`): nudge a
  generated test card into place, store the correction per machine
  (`images.calibration`). See TERMINALS.md for why this cannot be automatic.

## Guardrails

Three decisions meant to hold for every new feature:

**ImageMagick is never required — with four deliberate exceptions.** WezTerm
decodes PNG/JPEG/GIF/WebP/BMP itself. ImageMagick may *improve* features
(`:Image info`, `:Image compare`'s relative scaling) but never *enable* them —
otherwise the plugin depends on an installation on Windows again, and
experience says that is exactly why nothing ends up working. The first
exception is SVG: WezTerm fundamentally cannot decode it, so there is no route
without conversion. The second is `:Image export`: a PDF only comes out of
`magick`, there is no terminal-native alternative. The third is `:Image
redact`: the blacking out itself (painting pixels black) likewise only runs
through `magick`. The fourth is the ASCII fallback (`images.ascii`): reading
pixel colours out of an arbitrary raster file needs a real decoder, which plain
Lua does not have. All four report a clear error rather than failing silently
when ImageMagick is missing.

**No cell measurement.** `width`/`height` in cells plus
`preserveAspectRatio=1` leaves the work to the terminal. The moment pixels are
computed anywhere, the road back to `ioctl(TIOCGWINSZ)` is open — and that is
precisely where `snacks.image` fails on Windows.

This is also a limit rather than only a preference: the cell size cannot be
queried from inside Neovim at all (`:h TermResponse` forwards no CSI replies).
`display.cell_aspect` is therefore a configured value, and `:Image calibrate`
asks the user rather than the terminal — nudged by eye against a letterbox
strip, the same as `terminal_padding`. See TERMINALS.md.

**Low-level code does not notify.** `terminal`, `gallery` and `info` return
`ok, err` and never call `notify`. Only `lua/images/init.lua` decides what
reaches the user. Otherwise messages double up as soon as a module is called
from two directions.
