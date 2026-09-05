# Installation

## Prerequisites

- **Neovim 0.10+** — `vim.base64` and API level 14 (`nvim_ui_send`) are both
  used unconditionally.
- **A terminal that speaks OSC 1337.** WezTerm is the reference; iTerm2 and
  Konsole work too. Terminals without it fall back to coloured block graphics
  (`display.ascii_fallback`), which needs ImageMagick. `:Image check` reports
  what your terminal actually supports, and
  [architecture.md](architecture.md#detection-is-a-heuristic-and-stays-one)
  explains why that answer is a guess rather than a query.
- [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — **required**.
- **A clipboard image reader**, for `:Image paste` only: `wl-paste` (Wayland)
  or `xclip` (X11) on Linux, `pngpaste` on macOS (`brew install pngpaste`),
  `powershell.exe` on Windows — that one ships with the system.
  `:checkhealth images` names the one your platform needs.

## Optional external tools

Each unlocks a specific thing rather than gating the plugin. ImageMagick is the
one that appears in two roles — an improvement in some places, a hard
requirement in others; the full split is in
[architecture.md](architecture.md#where-imagemagick-is-a-requirement-rather-than-an-improvement).

| Tool | Unlocks | Required for |
| --- | --- | --- |
| **ImageMagick** (`magick`) | `:Image info` dimensions, `:Image compare`'s relative scaling | SVG display, the block-graphics fallback, `:Image redact`, `:Image export` (unless pdfport.nvim is installed), and `:Image scale` / `optimise` / `convert` |
| **`tesseract`** | — | `:Image ocr` |
| **`pdftoppm`** (poppler) | a `.pdf` entry in a host's picker previewing as its first page | — |
| [**pdfport.nvim**](https://github.com/StefanBartl/pdfport.nvim) | makes `:Image export` asynchronous and lossless via `img2pdf`; and, with `pdftoppm`, the PDF preview above | — |

`tesseract`'s language data installs separately, per language
(`tesseract-ocr-deu` and friends) — `:checkhealth images` lists what you have.
On Windows the UB-Mannheim installer leaves "Add to PATH" unticked, so a fresh
install routinely looks like no install at all; images.nvim probes
`C:/Program Files/Tesseract-OCR/` anyway, or set `ocr.bin`.

The block-graphics fallback is images.nvim's own (`images.ascii`, one coloured
`█` per cell over extmarks) and needs ImageMagick to read the pixels — it does
**not** shell out to `chafa` or `viu`, which are named in the source only as
the viewers that use the same technique.

`:Lib deps show images.nvim` reports all of it at any time, and the first
`setup()` after installing shows it once by itself
(`deps_popup = false` turns that off).

## lazy.nvim

```lua
{
  "StefanBartl/images.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Image" },
  ft = { "markdown", "vimwiki", "norg", "text" },
  opts = {},
}
```

Both triggers, not just `cmd`: the filetypes are what put the hover keymap and
the double-click handler in place in a Markdown buffer you have not run a
command in yet.

## packer.nvim

```lua
use {
  "StefanBartl/images.nvim",
  requires = { "StefanBartl/lib.nvim" }, -- required
  config = function()
    require("images").setup()
  end,
}
```

## vim-plug

```vim
Plug 'StefanBartl/lib.nvim' " required
Plug 'StefanBartl/images.nvim'

lua require("images").setup()
```

## Verifying the installation

```vim
:checkhealth images
:Image check
```

`:Image check` is the terminal-capability probe specifically: it says whether
OSC 1337 is getting through, which is the one thing `:checkhealth` cannot
answer from inside Neovim.
