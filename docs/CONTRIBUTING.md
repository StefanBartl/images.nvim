# Contributing to images.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/images.nvim/issues); pull requests
very welcome.

**Read [`architecture.md`](architecture.md) first.** It carries the OSC 1337
decision, what it takes to draw reliably, and the four costs that decision buys.
Three of the four limits people report as bugs are consequences of it, and are
written down there.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it to
the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/images.nvim")
require("images").setup({})
```

You need a terminal that speaks OSC 1337 — WezTerm, iTerm2 or Konsole — to see
anything. `:Image check` is the fastest way to find out whether yours does.

## Local commands

```bash
nvim --headless -u NONE -l TESTS/run.lua        # tests
nvim --headless -l scripts/gen_map.lua          # regenerate the module map
nvim --headless -l scripts/gen_map.lua --check  # verify it, write nothing
luacheck lua/ plugin/ scripts/ TESTS/ --globals vim
git config core.hooksPath scripts/hooks         # once per clone
```

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **Drawing is separated from everything else, and that separation is enforced.**
  The suite covers the side-effect-free modules only — grid layout, link
  detection, metadata formatting, config merging. Anything that draws needs a
  terminal with a graphics protocol and cannot be checked headless, which is why
  those parts are kept apart in the first place. `scripts/gen_map.lua` checks the
  split as a layer rule, so it stays an invariant rather than a note.
- **No Kitty graphics protocol.** Not as a fallback, not as an option. Supporting
  both means every drawing bug has two possible causes and no reproducible one,
  and the plugin exists precisely because Kitty sequences do not arrive on the
  target platform.
- **External tools unlock, they do not gate.** ImageMagick, `tesseract` and
  `pdftoppm` each buy one specific thing. Missing one costs that feature and
  nothing else, and `:checkhealth` says which and what it would buy. Declare new
  ones in [`install.json`](install.json) with the reasoning.
- **Terminal support is guessed, and the guess is admitted.** The protocol has no
  capability query. Where the code assumes, `:Image check` has to be able to
  contradict it.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/images/` | Display, capture, browsing and processing — the four feature groups |
| `lua/images/bindings/` | The `:Image` route tree, keymaps and the double-click handler |
| `lua/images/config/` | Defaults, `paste.dir` resolution, `setup()` validation |
| `lua/images/integrations/` | Soft-dependency bridges: the picker, nvzone/menu |
| `lua/images/@types/` | Shared type definitions |
| `lua/images/health.lua` | `:checkhealth images` |
| `scripts/` | Map generation, the layer check, git hooks |
| `docs/` | Everything the README links to |
| `TESTS/` | The headless suite — pure modules only |

## Adding a command

1. Decide which of the four groups it belongs to, and put it there — the grouping
   in [`FEATURES/`](FEATURES/README.md) is by what a feature is *for*, not by
   what it calls.
2. Keep the computation pure and the drawing separate. If your new code cannot be
   tested headless, check whether the untestable part is really more than the
   final draw call.
3. If it needs an external tool, declare it in [`install.json`](install.json),
   report on it in `health.lua`, and make its absence cost that command only.
4. Route it in `lua/images/bindings/` with completion.
5. Add a spec under `TESTS/` for the pure part.
6. Document it in [`commands.md`](commands.md), the matching `FEATURES/` page,
   and [`BINDINGS.md`](BINDINGS.md).

## Tests

`TESTS/run.lua` runs headless.
[GitHub Actions](../.github/workflows/ci.yml) runs it, luacheck and the module-map
check on every push and PR to `main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
