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

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into your document. Built on
[lib.nvim](https://github.com/StefanBartl/lib.nvim) as a deliberate shared
dependency.

```
:Image                     show the image under the cursor
:Image gallery             every image in the buffer, side by side
:Image paste               clipboard screenshot → file next to the document + link
:Image next / prev         walk through the images of the buffer
:'<,'>Image list           pick from the images in the selection
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
| `:Image pin` | Keep the image on screen instead of clearing on cursor move |
| `:Image check` | Report whether this terminal can display images |
| `:Image clear` | Remove displayed images |

In markdown buffers, `<leader>im` shows the image under the cursor, `<leader>ig`
opens the gallery, `<leader>in`/`<leader>ip` walk through the images,
`<leader>iv` pastes from the clipboard, and a double-click on a link shows the
image. A double-click that does not hit an
image link falls through to the normal word selection.

`:Image paste` is the everyday case for documentation: take a screenshot, run
it, and the PNG is written to `assets/<document>-<timestamp>.png` with
`![](assets/…)` inserted at the cursor.

## Configuration

```lua
require("images").setup({
  command = "Image",
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp" },
  display = {
    max_cols = 60,   -- in terminal cells, not pixels
    max_rows = 25,
    gallery_gap = 1, -- cells between gallery tiles
    assume_supported = false, -- true silences the "unknown terminal" warning
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
  },
  paste = {
    dir = "assets",              -- "" puts the file next to the document
    name_template = "%s-%d.png", -- document stem, timestamp
    link_template = "![](%s)",
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

## Integrations

`markdown.nvim` is used for link resolution when present, falling back to an
internal resolver otherwise — a soft dependency, never required.

`lib.nvim` provides the `:Image` command grammar (`usercmd.composer`) and the
picker used by `:Image list`; without its UI kit the picker falls back to
`vim.ui.select`.

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
