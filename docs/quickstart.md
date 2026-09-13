# Quickstart

Open a markdown file and put the cursor on an image link. That is the whole
first step — no command needed.

Then, if nothing appears, the two checks answer why:

```vim
:checkhealth images        " terminal, clipboard tool and dependencies
:Image check                " specifically: is OSC 1337 getting through
```

And the command that earns its place fastest:

```vim
:Image paste                " clipboard screenshot -> a file next to the document, link written
```

See [health.md](health.md) for what each line of `:checkhealth` means, and
[what-you-get.md](what-you-get.md) for the rest of the day-one command table.
