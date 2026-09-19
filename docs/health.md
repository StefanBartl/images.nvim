# Health

```vim
:checkhealth images
```

Reports, in order, everything the plugin can check about the machine it is
running on:

| Check | Answers |
| --- | --- |
| **output** | Is `nvim_ui_send` available at all — without it no image can be drawn, on any terminal |
| **terminal** | Which terminal was detected, and whether it is believed to speak OSC 1337 (or whether support is only being assumed via `display.assume_supported`) |
| **clipboard** | Which platform-specific tool `:Image paste` will use — `powershell.exe` on Windows, `pngpaste` on macOS, `wl-paste`/`xclip` on Linux |
| **screenshot** | Whether `:Image screenshot` has a tool to call on this platform; its absence only costs that one command, `:Image paste` keeps working either way |
| **ImageMagick** | Whether `magick` is on `PATH`, and what stays on without it (`:Image info` dimensions, `:Image compare`'s relative scaling, SVG display) versus what needs it outright (`:Image export`/`redact`/`scale`/`optimise`/`convert`) |
| **block graphics** | Prints a sample row of each ASCII-fallback geometry (`half`, `quadrant`, `sextant`) so you can read off which one this terminal actually renders as shapes rather than replacement boxes — see [configuration.md](configuration.md#displayascii_fallback) |
| **OCR** | Whether `tesseract` was found (and by which of the three lookup routes), which language data is installed, and whether the configured `ocr.lang` is among it |
| **PDF** | Whether a PDF entry can be previewed as its first page — separately reporting `pdf.enabled = false`, `pdfport.nvim` missing, and `pdftoppm` missing, since each has a different fix |
| **config** | Any `setup()` option the last call had to reject — an unknown key (with a "did you mean" guess) or one given the wrong shape — so a typo does not just silently keep its default forever |
| **calibration** | Whether the stored `stdpath("data")/images.nvim/calibration.json` failed to decode; a corrupt file behaves like no calibration at all, but unlike a missing one it is worth knowing about |
| **dependencies** | `lib.nvim` (required, errors if missing) and `markdown.nvim` (optional, only changes which path resolver is used) |
| **declared tools** | A pointer into `:Lib deps show images.nvim`, generated from [install.json](install.json) — only shown when the installed `lib.nvim` supports it |

## Two probes `:checkhealth` cannot replace

`:checkhealth images` answers **is everything present**. Two narrower
questions need a different command:

- `:Image check` — re-runs the terminal capability probe and says whether
  OSC 1337 is actually getting through *right now*, which is the one thing
  `:checkhealth` cannot answer from inside Neovim (the protocol has no
  capability query).
- `:Image debug <mode>` — measures where a draw actually landed, when an
  image appears but not where it was asked to be.

The symptoms that have a cause rather than a bug behind them, and which of
the three answers which, are in [troubleshooting.md](troubleshooting.md).
