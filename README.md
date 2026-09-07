> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

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
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-lightgrey)

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into your document.

It speaks the **iTerm2 inline-image protocol (OSC 1337)** rather than the Kitty
graphics protocol the alternatives rely on — which is what makes it work on
native Windows Neovim in WezTerm, where they do not.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at the [documentation index](docs/README.md), which says what is where and
which question each page answers.

- [Features](docs/FEATURES/README.md) — everything the plugin does, four pages grouped by purpose.
- [Installation](docs/installation.md) — requirements, the terminal question, and a spec per plugin manager.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) — every `:Image` route, with arguments, ranges and examples.
- [Bindings](docs/BINDINGS.md) — the cheatsheet: keymaps, user commands, autocommands.
- [Workflow](docs/WORKFLOW.md) — how the commands combine day to day, rather than what each one does.
- [Troubleshooting](docs/troubleshooting.md) — the symptoms that have a cause rather than a bug behind them.
- [Architecture](docs/architecture.md) — the OSC 1337 decision, what it takes to draw reliably, and the four costs it buys.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a command.

`:help images` is the same material as Vim help. The module map is generated,
not committed — it is derived output and stale the moment anything changes. Open
any file in this repository and run `:DocMap` to build it, via
[documentation.nvim](https://github.com/StefanBartl/documentation.nvim).

---

## What it does

`snacks.image` and `image.nvim` both draw through the Kitty graphics protocol.
On native Windows Neovim in WezTerm, Kitty sequences coming from Neovim are never
drawn — no error, no configuration that fixes it, nothing on screen. That is the
whole reason this plugin exists.

It uses the iTerm2 inline-image protocol (OSC 1337) instead, which does get
through. That one decision is also where its four limits come from: no images
inline in the text flow, whole-cell placement, SVG needing ImageMagick, and
terminal support that has to be guessed because the protocol has no capability
query. All four, and the measurements behind them, are in
[docs/architecture.md](docs/architecture.md).

On top of drawing, four groups of work — the split is by what each feature is
*for*, and it is the same split [docs/FEATURES/](docs/FEATURES/README.md) uses:

| Group | Covers |
| --- | --- |
| **Display** | The image under the cursor, a gallery of the buffer, full-screen zen, side-by-side compare at true relative size |
| **Capture** | Clipboard paste into a file next to the document with the link written for you, interactive screenshot, redaction before sharing |
| **Browsing** | Walking the buffer's images, finding orphans nothing links to, browsing every image under the cwd with a live preview |
| **Processing** | OCR, scale, optimise, convert — each producing a copy beside the source |

---

## Around it

> **[markdown.nvim](https://github.com/StefanBartl/markdown.nvim)** — resolves
> the link targets this plugin renders: Markdown links, `<img>` tags, `<figure>`
> blocks. It prefers images.nvim as its own in-Neovim preview provider in return.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — answers "what is
> this" about whatever the cursor rests on, in any filetype. images.nvim is its
> picture provider, so a path to a PNG previews as the PNG.
>
> **[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — meets it from
> both sides: it turns an image into a PDF for `:Image export`, and a PDF page
> back into an image so a `.pdf` entry previews as its first page.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** for `vim.base64`, with API level 14 for `nvim_ui_send` |
| A terminal that speaks OSC 1337 | required — WezTerm, iTerm2, Konsole. `:Image check` answers whether yours does |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Image` command tree and the shared helpers |

Nothing beyond that is required. Each of the following unlocks a specific thing
rather than gating the plugin:

| | |
| --- | --- |
| ImageMagick | SVG rendering, scale, optimise, convert |
| `tesseract` | `:Image ocr` |
| poppler's `pdftoppm` | PDF pages as images |
| A clipboard tool | `:Image paste` — which one depends on the platform |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | `:Image pickers cwd` with a live preview |

`:Lib deps show images.nvim` says at any time which are present and what each
would buy — declared, with the reasoning per tool, in
[docs/install.json](docs/install.json).

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/images.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Image" },
  ft = { "markdown", "vimwiki", "norg", "text" },
  opts = {},
}
```

Both triggers, not just `cmd`: the filetypes are what put the hover keymap and
the double-click handler in place in a Markdown buffer you have not run a command
in yet.

packer.nvim, vim-plug and the full prerequisite list are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Open a markdown file and put the cursor on an image link. That is the whole first
step — no command needed.

Then, if nothing appears, the two checks answer why:

```vim
:checkhealth images        " terminal, clipboard tool and dependencies
:Image check               " specifically: is OSC 1337 getting through
```

And the command that earns its place fastest:

```vim
:Image paste               " clipboard screenshot -> a file next to the document, link written
```

---

## What you get with the defaults

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

Every route with its arguments is in [docs/commands.md](docs/commands.md); every
key is in [docs/BINDINGS.md](docs/BINDINGS.md).

---

## Health check

```vim
:checkhealth images
```

Reports which terminal was detected and whether it is believed to speak OSC 1337,
which clipboard tool is available for `:Image paste`, and which of ImageMagick,
`tesseract` and `pdftoppm` are present and what each one would unlock.

`:Image check` is the narrower question: it sends a sequence and asks whether it
was actually drawn — which is the only real answer, since the protocol has no
capability query. The symptoms with a cause rather than a bug behind them are in
[docs/troubleshooting.md](docs/troubleshooting.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules, the project
layout and the local commands (tests, module map, luacheck, hooks);
[docs/architecture.md](docs/architecture.md) explains the drawing/pure split that
the test suite depends on.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/images.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/images.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
