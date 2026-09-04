# images.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first — including which terminals can draw at all — and a spec per plugin manager |

## Using it

| Page | Answers |
| --- | --- |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand this plugin registers |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each command does, but how they combine — pasting a screenshot into a document, keeping the folder tidy, and finding the image you half remember |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES/](FEATURES/README.md) | Four pages, grouped by what a feature is *for* rather than by source file: putting pixels on screen, getting images onto disk and converting them, finding and comparing them, and how this plugin fits with its neighbours. The overview also states the choice the rest follows from — the iTerm2 protocol rather than Kitty's, which is why this draws on WezTerm and native Windows |

## Here, but not prose

**`install.json`** declares the external tools this plugin can use — the
converters, the OCR, the screenshot tool — machine-readably, for
`:Lib deps show images.nvim`. What each is *for* is in
[installation.md](installation.md) and in
[FEATURES/CAPTURE.md](FEATURES/CAPTURE.md).
