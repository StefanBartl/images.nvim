# ROADMAP — images.nvim

Ideas that are not implemented yet. Nothing here is a commitment.

## Consumers in sibling plugins

- **filetree.nvim** — the preview feature already has an
  `image.backend = "auto" | "snacks" | "image.nvim" | "system" | false` switch
  and an `open_image()` dispatcher. Add `"images.nvim"` as a backend and let
  `"auto"` prefer it, so `<Tab>` previews and `<CR>` opens work on Windows.
- **open.nvim** — `:Open image [images|system]`, so the image case joins the
  existing handler grammar instead of needing its own command.
- **pickers.nvim** — show the image in the picker preview pane. Needs the
  preview window's screen position, which the picker knows and this plugin
  does not.

## Display

- Draw into a floating window rather than over the text, so the image survives
  cursor movement and can be scrolled with the buffer.
- Keep the image visible until dismissed (toggle instead of auto-clear).
- Multiple images at once, e.g. all images of a section side by side.
- Remote images (`https://…`) via a download to a cache directory.

## Paste

- Take a screenshot directly instead of reading the clipboard (Windows:
  `Snipping Tool`, Linux: `grim`/`maim`, macOS: `screencapture`).
- Ask for a filename instead of using the timestamp template.
- Fill in the alt text from a prompt, so `![](…)` becomes `![…](…)`.
- Optimise the PNG on save when `magick` is available.

## Terminal support

- Sixel as a second backend, for terminals that speak it but not OSC 1337.
- Kitty APC as a third backend for Kitty and Ghostty, where it works and
  supports Unicode placeholders — which would unlock true inline rendering on
  those terminals.
- Auto-detect the protocol instead of assuming OSC 1337.

## Literatur und Referenzen

- [iTerm2 Inline Images Protocol](https://iterm2.com/documentation-images.html)
  — the OSC 1337 `File=` sequence this plugin emits.
- [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  — the alternative used by snacks.image and image.nvim, including the Unicode
  placeholder mechanism required for inline rendering.
- [WezTerm — Imgcat and image protocols](https://wezfurlong.org/wezterm/imgcat.html)
  — which protocols WezTerm implements and their limits.
