> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# images.nvim

```
  ___
 |_ _|_ __  __ _ __ _ ___ ___
  | || '  \/ _` / _` / -_|_-<
 |___|_|_|_\__,_\__, \___/__/
                |___/
        show images inside Neovim, on any terminal that speaks OSC 1337
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-active%20development-blue)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-lightgrey)

---

> Pairs well with [markdown.nvim](https://github.com/StefanBartl/markdown.nvim):
> it resolves the link targets — Markdown links, `<img>` tags, `<figure>`
> blocks — that this plugin then renders, and prefers images.nvim as its own
> in-Neovim preview provider in return.
>
> And with [hover.nvim](https://github.com/StefanBartl/hover.nvim), which
> answers "what is this" about whatever the cursor rests on, in any filetype:
> images.nvim is its picture provider, so a path to a PNG previews as the PNG.
>
> [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) meets it from
> both sides — it turns an image into a PDF for `:Image export`, and a PDF page
> back into an image so a `.pdf` entry previews as its first page.

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into your document.

It speaks the **iTerm2 inline-image protocol (OSC 1337)** rather than the Kitty
graphics protocol that `snacks.image` and `image.nvim` rely on — because on
native Windows Neovim in WezTerm, Kitty sequences coming from Neovim are never
drawn, which makes those plugins unusable there regardless of configuration.
That one decision is also where this plugin's four limits come from: no images
inline in the text flow, whole-cell placement, SVG needing ImageMagick, and
terminal support that has to be guessed because the protocol has no capability
query. All four, and the measurements behind them, are in
[docs/architecture.md](docs/architecture.md).

---

## Table of contents

- [Quickstart](#quickstart)
- [What you get](#what-you-get)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

---

## Quickstart

Requires Neovim **0.10+** (for `vim.base64`) with API level 14 (for
`nvim_ui_send`), a terminal that speaks OSC 1337 (WezTerm, iTerm2, Konsole),
and [lib.nvim](https://github.com/StefanBartl/lib.nvim).

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

Open a markdown file and put the cursor on an image link — that is the whole
first step; no command is needed. Then:

```
:checkhealth images        terminal, clipboard tool and dependencies
:Image check               specifically: is OSC 1337 getting through
```

For packer.nvim, vim-plug and the full prerequisite list, see
[docs/installation.md](docs/installation.md).

---

## What you get

```
:Image                     show the image under the cursor
:'<,'>Image                gallery of just the selected lines
:Image gallery             every image in the buffer, side by side
:Image paste               clipboard screenshot → file next to the document + link
:Image screenshot          take a screenshot interactively, skipping the clipboard step
:Image next / prev         walk through the images of the buffer
:Image orphans             images in paste.dir that nothing links to anymore
:Image calibrate           measure this terminal's image placement, once, interactively
:Image pickers cwd         browse every image under cwd, live preview with snacks.picker
:Image zen                 the image under the cursor, full-screen, in a real window
:Image compare cwd         pick two images, view side by side at their true relative size
:Image ocr                 read the text out of the image under the cursor, into a buffer
:Image redact              black out boxes before sharing a screenshot
:Image scale 800x          resized copy next to the source, aspect preserved
:Image optimise            smaller copy: metadata stripped, best compression
:Image convert png         copy in another format, same stem
```

In markdown buffers, `<leader>im` shows the image under the cursor,
`<leader>ig` opens the gallery, `<leader>in`/`<leader>ip` walk through them,
`<leader>iv` pastes from the clipboard, `<leader>is` takes a screenshot, and a
double-click on a link shows the image.

Grouped by what each feature is *for* — putting pixels on screen, getting them
onto disk, finding them again, and fitting in with the neighbours — in
[docs/FEATURES/](docs/FEATURES/README.md). Every route with its arguments is in
[docs/commands.md](docs/commands.md); the full option list is in
[docs/configuration.md](docs/configuration.md).

Nothing beyond lib.nvim is required. ImageMagick, `tesseract` and poppler's
`pdftoppm` each unlock a specific thing rather than gating the plugin, and
`:Lib deps show images.nvim` says at any time which are present and what each
would buy — declared, with the reasoning per tool, in
[`docs/install.json`](docs/install.json).

---

## Documentation

Start at the [documentation index](docs/README.md), which says what is where
and which question each page answers.

- [Features](docs/FEATURES/README.md) — everything the plugin does, four pages grouped by purpose.
- [Installation](docs/installation.md) — requirements, the terminal question, and a spec per plugin manager.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) — every `:Image` route, with arguments, ranges and examples.
- [Bindings](docs/BINDINGS.md) — the cheatsheet: keymaps, user commands, autocommands.
- [Workflow](docs/WORKFLOW.md) — how the commands combine day to day, rather than what each one does.
- [Troubleshooting](docs/troubleshooting.md) — the symptoms that have a cause rather than a bug behind them.
- [Architecture](docs/architecture.md) — the OSC 1337 decision, what it takes to draw reliably, and the four costs it buys.

Also `:help images` for the same material as Vim help.

The module map is generated, not committed — it is derived output and stale the
moment anything changes. Open any file in this repo and run `:DocMap` to build
it, via [documentation.nvim](https://github.com/StefanBartl/documentation.nvim).

---

## Development

```bash
nvim --headless -u NONE -l TESTS/run.lua        # tests
nvim --headless -l scripts/gen_map.lua          # regenerate the module map
nvim --headless -l scripts/gen_map.lua --check  # verify it, write nothing
luacheck lua/ plugin/ scripts/ TESTS/ --globals vim
git config core.hooksPath scripts/hooks         # once per clone
```

The suite covers the side-effect-free modules only — grid layout, link
detection, metadata formatting, config merging. Anything that draws needs a
terminal with a graphics protocol and cannot be checked headless, which is why
those parts are separated from the rendering in the first place.
`scripts/gen_map.lua` enforces that split as a layer rule, so it stays a
checked invariant rather than a note in a document.

## License

MIT — see [LICENSE](LICENSE).
