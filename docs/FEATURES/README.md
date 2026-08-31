# images.nvim features

images.nvim shows images inside Neovim's terminal using the iTerm2 (OSC
1337) protocol instead of the Kitty graphics protocol every other image
plugin relies on — the deliberate choice that makes it work on WezTerm and
native Windows, where Kitty-only plugins draw nothing. Features below are
grouped by what they're for, not by source file:

- **DISPLAY.md** — actually putting pixels on screen: the single-image
  path, hover, the ASCII fallback, remote images, the zen window, terminal
  capability detection.
- **CAPTURE.md** — getting images onto disk and linked from a document, and
  turning one into another: paste, screenshot, replace, export, redact,
  scale, optimise, convert, OCR.
- **BROWSING.md** — finding and comparing images across a buffer or a
  directory tree: list, gallery, next/prev, pickers, compare, orphans.
- **INTEGRATIONS.md** — how images.nvim fits with lib.nvim, markdown.nvim,
  snacks.nvim, filetree.nvim, open.nvim, and pdfport.nvim.
