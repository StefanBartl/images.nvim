# What it does and what not

`snacks.image` and `image.nvim` both draw through the Kitty graphics protocol.
On native Windows Neovim in WezTerm, Kitty sequences coming from Neovim are
never drawn — no error, no configuration that fixes it, nothing on screen.
That is the whole reason this plugin exists.

It uses the iTerm2 inline-image protocol (OSC 1337) instead, which does get
through. That one decision is also where its four limits come from: no images
inline in the text flow, whole-cell placement, SVG needing ImageMagick, and
terminal support that has to be guessed because the protocol has no
capability query. All four, and the measurements behind them, are in
[architecture.md](architecture.md).

On top of drawing, four groups of work — the split is by what each feature is
*for*, and it is the same split [FEATURES/](FEATURES/README.md) uses:

| Group | Covers |
| --- | --- |
| **Display** | The image under the cursor, a gallery of the buffer, full-screen zen, side-by-side compare at true relative size |
| **Capture** | Clipboard paste into a file next to the document with the link written for you, interactive screenshot, redaction before sharing |
| **Browsing** | Walking the buffer's images, finding orphans nothing links to, browsing every image under the cwd with a live preview |
| **Processing** | OCR, scale, optimise, convert — each producing a copy beside the source |

Everything runs through the single `:Image` command tree — see
[commands.md](commands.md) for every route, argument and example.
