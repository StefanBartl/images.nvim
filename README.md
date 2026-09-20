> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# images.nvim

```
██╗███╗   ███╗ █████╗  ██████╗ ███████╗███████╗
██║████╗ ████║██╔══██╗██╔════╝ ██╔════╝██╔════╝
██║██╔████╔██║███████║██║  ███╗█████╗  ███████╗
██║██║╚██╔╝██║██╔══██║██║   ██║██╔══╝  ╚════██║
██║██║ ╚═╝ ██║██║  ██║╚██████╔╝███████╗███████║
╚═╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝
                                          .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-lightgrey)
[![CI](https://github.com/StefanBartl/images.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/images.nvim/actions/workflows/ci.yml)

images.nvim shows images in the terminal without leaving Neovim: hover a
markdown link, double-click it, or paste a screenshot straight from the
clipboard into the document. It draws through the iTerm2 inline-image
protocol (OSC 1337) instead of the Kitty graphics protocol the alternatives
rely on, which is what makes it work on native Windows Neovim in WezTerm,
where they do not.

---

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
> dependency — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, the terminal question, and the one required plugin.
- [Installation](docs/installation.md) — plugin managers and optional external tools.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the sixteen `:Image` routes and the six keymaps that matter on day one.
- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)

### The Rest

- [What it does and what not](docs/scope.md) — the four feature groups, and the four limits the OSC 1337 decision buys.
- [How the commands combine day to day](docs/WORKFLOW.md)
- [Why it does it that way](docs/architecture.md)
- [Health check](docs/health.md) — what `:checkhealth images` reports, check by check.
- [Troubleshooting](docs/troubleshooting.md) — the symptoms that have a cause rather than a bug behind them.
- [Contributing](docs/CONTRIBUTING.md)
- [Feedback](https://github.com/StefanBartl/images.nvim/issues)

`:help images` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

images.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
