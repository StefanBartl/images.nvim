<pre>
  ___
 |_ _|_ __  __ _ __ _ ___ ___
  | || '  \/ _` / _` / -_|_-<
 |___|_|_|_\__,_\__, \___/__/
                |___/
        show images inside Neovim, on any terminal that speaks OSC 1337
</pre>

![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Made%20with-Lua-2C2D72?logo=lua&logoColor=white)
![Depends](https://img.shields.io/badge/depends-lib.nvim-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-lightgrey)

---

> Writing documentation with a lot of links and images?
> [markdown.nvim](https://github.com/StefanBartl/markdown.nvim) resolves the
> link targets that this plugin renders.

## Table of Contents

- [Why not snacks.image or image.nvim](#why-not-snacksimage-or-imagenvim)
- [Quickstart](#quickstart)
- [Usage](#usage)
- [Configuration](#configuration)
- [Integrations](#integrations)
- [Documentation](#documentation)
- [Development](#development)

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into your document. Built on
[lib.nvim](https://github.com/StefanBartl/lib.nvim) as a deliberate shared
dependency.

```
:Image                     show the image under the cursor
:'<,'>Image                gallery of just the selected lines
:Image gallery             every image in the buffer, side by side
:Image paste               clipboard screenshot → file next to the document + link
:Image next / prev         walk through the images of the buffer
:'<,'>Image list           pick from the images in the selection
:Image orphans             images in paste.dir that nothing links to anymore
:Image pickers cwd         browse every image under cwd, live preview with snacks.picker
:Image zen                 the image under the cursor, full-screen, in a real window
:Image compare cwd         pick two images, view side by side at their true relative size
```

## Why not snacks.image or image.nvim

Both speak only the Kitty graphics protocol. On native Windows Neovim running
in WezTerm, Kitty APC sequences (`ESC _G`) are never drawn when they come from
Neovim — the very same sequences work from a raw shell, so the difference is
introduced by Neovim's output layer. That makes both plugins unusable there,
regardless of configuration.

images.nvim uses the iTerm2 protocol (OSC 1337) instead, which works
reliably. Three details that matter, all of them learned the hard way:

- Output goes through `vim.api.nvim_ui_send`, not `io.stdout:write` — the
  latter only draws once per terminal session.
- The cursor is saved and positioned first (`ESC[s` / `ESC[<row>;<col>H` /
  payload / `ESC[u`). Without that the image lands below the statusline and
  pushes it up.
- `width` and `height` are given in **cells**, together with
  `preserveAspectRatio=1`. The terminal does the scaling, so the pixel size of
  a cell never has to be known — which is exactly where snacks.image breaks on
  Windows, since its `ioctl(TIOCGWINSZ)` path cannot work there.

Before the first draw the terminal is checked against the small set that
implements OSC 1337 (WezTerm, iTerm2, Konsole), detected from environment
variables. An unknown terminal produces a warning **once per session** and the
image is still drawn — the protocol has no capability query, so this is a
heuristic, and a false negative must not break a working setup. Silence it
with `display.assume_supported = true`; `:Image check` re-runs the detection.

Inline images in the text flow are not possible on WezTerm: they require
Unicode placeholders, which only Kitty and Ghostty implement and neither ships
for Windows. images.nvim draws over the text instead, and clears on the next
cursor move.

SVG is the one format WezTerm cannot decode at all — everything else
(PNG/JPEG/GIF/WebP/BMP) it handles itself. With ImageMagick installed, an
`.svg` file is rasterized to a cached PNG before drawing; without it, opening
one reports a clear error instead of failing silently. This is deliberately
the *only* place ImageMagick is a requirement rather than an improvement —
see [Configuration](#configuration).

## Quickstart

Requires Neovim 0.10+ (for `vim.base64`) with API level 14 (for
`nvim_ui_send`), and [lib.nvim](https://github.com/StefanBartl/lib.nvim).

```lua
{
  "StefanBartl/images.nvim",
  ft = { "markdown", "vimwiki", "norg", "text" },
  dependencies = { "StefanBartl/lib.nvim" },
  opts = {
    -- optional, see Configuration
  },
},
```

Run `:checkhealth images` to verify that your terminal, clipboard tool and
dependencies are in place.

## Usage

| Command | What it does |
| --- | --- |
| `:Image` | Show the image under the cursor |
| `:Image show [path]` | Show a specific file, or the one under the cursor |
| `:Image list` | Pick from every image link in the buffer |
| `:'<,'>Image list` | …restricted to the selected lines |
| `:Image gallery [cols]` | Show every image of the buffer side by side in a grid |
| `:Image next` / `prev` | Jump to the next/previous image and show it |
| `:Image info [path]` | Format, dimensions and file size |
| `:Image paste` | Save the clipboard image next to the document and insert the link |
| `:Image replace [path]` | Overwrite an existing image with the clipboard, keep the link |
| `:Image orphans` | Find images in `paste.dir` that no link points to, offer to delete |
| `:Image pickers [cfile\|cwd\|path] [dir]` | Browse images under cfile/cwd/an explicit dir; live preview with snacks.picker, falls back to a plain list. `<Tab>` multi-selects (snacks), confirming shows them as a gallery instead of one image |
| `:Image zen [path]` | Show one image full-screen, in a real editable window — survives a snacks hover popup open alongside it |
| `:Image compare [cfile\|cwd\|path] [dir]` | Pick two images from a scan, view side by side; with ImageMagick, scaled proportionally so a small icon doesn't look the same size as a large photo |
| `:Image pin` | Keep the image on screen instead of clearing on cursor move |
| `:Image check` | Report whether this terminal can display images |
| `:Image clear` | Remove displayed images (and a `:Image zen` window, if open) |

In markdown buffers, `<leader>im` shows the image under the cursor, `<leader>ig`
opens the gallery, `<leader>in`/`<leader>ip` walk through the images,
`<leader>iv` pastes from the clipboard, and a double-click on a link shows the
image. With [which-key](https://github.com/folke/which-key.nvim) installed,
`<leader>i` shows up as a named group — detected from whichever of the above
keys share a common prefix, so a fully remapped set of keys still groups
correctly. A double-click that does not hit an
image link falls through to the normal word selection.

`:Image paste` is the everyday case for documentation: take a screenshot, run
it, and the PNG is written to `assets/<document>-<timestamp>.png` with
`![](assets/…)` inserted at the cursor.

## Configuration

```lua
require("images").setup({
  command = "Image",
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" }, -- svg needs ImageMagick to draw
  display = {
    max_cols = 60,   -- in terminal cells, not pixels
    max_rows = 25,
    gallery_gap = 1, -- cells between gallery tiles
    assume_supported = false, -- true silences the "unknown terminal" warning
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    browse_exclude = { ".deps", "node_modules" }, -- dirs :Image pickers skips (".git" is always skipped)
    zen = { width = 0.9, height = 0.85 },          -- :Image zen window size, as a fraction of the editor
  },
  paste = {
    dir = "assets",              -- "" puts the file next to the document
    name_template = "%s-%d.png", -- document stem, timestamp
    link_template = "![](%s)",
    ask_filename = false,        -- true prompts for a name, prefilled with the template
  },
  keymaps = {
    show = "<leader>im",  -- every entry accepts false to disable it
    gallery = "<leader>ig",
    next = "<leader>in",
    prev = "<leader>ip",
    paste = "<leader>iv",
    double_click = true,
    filetypes = { "markdown", "vimwiki", "norg", "text" },
  },
})
```

`paste.ask_alt_text = true` prompts for alt text before inserting the link
(via lib.nvim's UI kit when available), producing `![alt](path)` instead of
`![](path)`. Cancelling the prompt still inserts the link, just without alt
text — the file is already on disk by then, and a lost link would be the
worse surprise.

`paste.ask_filename = true` prompts for a filename before writing the
clipboard image, prefilled with what `paste.name_template` would have
produced. Any path component in the answer is dropped — only the name
itself is used — and the extension is always forced to `.png`, since that is
what gets written regardless of what you type. Cancelling here does nothing
at all: unlike the alt-text prompt, nothing has been read from the clipboard
yet at this point, so cancel means cancel.

A statusline segment:

```lua
{ require("images").statusline }  -- "" when nothing is shown, else an icon
```

## Integrations

`markdown.nvim` is used for link resolution when present, falling back to an
internal resolver otherwise — a soft dependency, never required.

`lib.nvim` provides the `:Image` command grammar (`usercmd.composer`), the
picker used by `:Image list`, and the `kit.compare` component behind
`:Image compare`; without its UI kit the picker falls back to `vim.ui.select`.

[snacks.nvim](https://github.com/folke/snacks.nvim)'s picker is a soft
dependency for `:Image pickers`: with it installed, browsing shows a live
image thumbnail per entry (a custom preview function, not snacks.image's own
Kitty-only one — see "Why not snacks.image or image.nvim" above); without it,
`:Image pickers` falls back to a plain list with no preview.

`filetree.nvim` uses this plugin as the first backend of its preview feature,
and `open.nvim` routes `:Open image` here. See
[docs/ROADMAP/CROSS-PLUGIN.md](docs/ROADMAP/CROSS-PLUGIN.md) for what else is
possible across the sibling plugins.

## Documentation

- `:h images` — vimdoc reference
- [docs/BINDINGS.md](docs/BINDINGS.md) — every keymap, user command and autocmd
- [docs/map/](docs/map/) — generated module map ([documentation.nvim](https://github.com/StefanBartl/documentation.nvim))
- [docs/ROADMAP/](docs/ROADMAP/) — planned features and cross-plugin ideas

## Development

```bash
nvim --headless -u NONE -l TESTS/run.lua        # tests
nvim --headless -l scripts/gen_map.lua          # regenerate the module map
nvim --headless -l scripts/gen_map.lua --check  # verify it, write nothing
luacheck lua/ plugin/ scripts/ TESTS/ --globals vim
```

The suite covers the side-effect-free modules only — grid layout, link
detection, metadata formatting, config merging. Anything that draws needs a
terminal with a graphics protocol and cannot be checked headless, which is
why those parts are separated from the rendering in the first place.
`scripts/gen_map.lua` enforces that split as a layer rule, so it stays a
checked invariant rather than a note in a document.

Install the pre-commit hook once per clone:

```bash
git config core.hooksPath scripts/hooks
```
