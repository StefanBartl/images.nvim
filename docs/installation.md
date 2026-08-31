# Installation

## Prerequisites

- **Neovim 0.10+** — `vim.base64` and API level 14 (`nvim_ui_send`) are both
  used unconditionally.
- **A terminal that speaks OSC 1337.** WezTerm is the reference; iTerm2 works
  too. Terminals without it fall back to coloured block graphics
  (`display.ascii_fallback`), which needs ImageMagick. `:Image check` reports
  what your terminal actually supports.
- [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — **required**.

Optional, and each one only unlocks a specific thing rather than gating the
plugin — see [Optional external tools](../README.md#optional-external-tools)
for the full reasoning:

- **ImageMagick** — `:Image info` dimensions, `:Image compare`'s relative
  scaling, SVG display, and required outright for `:Image redact`, the ASCII
  fallback, and the three file operations `:Image scale` / `:Image optimise` /
  `:Image convert`.
- **`chafa`** — the terminal-image fallback renderer.
- **`tesseract`** — required outright for `:Image ocr`, which reads the text
  out of an image. The language data installs separately per language
  (`tesseract-ocr-deu` and friends); `:checkhealth images` lists what you
  have. On Windows the UB-Mannheim installer leaves "Add to PATH" unticked —
  images.nvim probes `C:/Program Files/Tesseract-OCR/` anyway, or set
  `ocr.bin`.
- [`pdfport.nvim`](https://github.com/StefanBartl/pdfport.nvim) — makes
  `:Image export` asynchronous and lossless; without it, export falls back to
  a synchronous `magick`-only path.

`:Lib deps show images.nvim` reports all of it at any time, and the first
`setup()` after installing shows it once by itself.

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
