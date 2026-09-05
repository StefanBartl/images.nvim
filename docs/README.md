# images.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first — including which terminals can draw at all — a spec per plugin manager, and what each optional external tool unlocks |
| [configuration.md](configuration.md) | Every `setup()` option, its default, and what it is for. Including the three placement options, which are one topic rather than three |

## Using it

| Page | Answers |
| --- | --- |
| [commands.md](commands.md) | Every `:Image` route with its arguments, ranges and examples — the usage, not the one-liner |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand this plugin registers, one line each |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each command does, but how they combine — pasting a screenshot into a document, keeping the folder tidy, and finding the image you half remember |
| [troubleshooting.md](troubleshooting.md) | The symptoms that have a cause rather than a bug behind them, and which of `:checkhealth images` / `:Image check` / `:Image debug` answers which question |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [architecture.md](architecture.md) | Why OSC 1337 rather than the Kitty protocol every other image plugin uses, what it takes to draw through it reliably, and the four limits that follow — inline placement, whole-cell positioning, SVG, and capability detection |
| [FEATURES/](FEATURES/README.md) | Four pages, grouped by what a feature is *for* rather than by source file: putting pixels on screen, getting images onto disk and converting them, finding and comparing them, and how this plugin fits with its neighbours |

## Here, but not prose

**`install.json`** declares the external tools this plugin can use — the
converters, the OCR, the PDF rasterizer — machine-readably, for
`:Lib deps show images.nvim`. What each is *for* is in
[installation.md](installation.md#optional-external-tools) and in
[FEATURES/CAPTURE.md](FEATURES/CAPTURE.md).

**`doc/images.txt`** is the same material as Vim help: `:help images`.
