# Capture

Getting an image onto disk, linked from the current document, or turned
into something else.

## Paste from clipboard

Saves the clipboard image next to the document and inserts a markdown
link at the cursor. Writes to `assets/<document>-<timestamp>.png` by
default — unless a `Resources`/`Ressourcen` folder already exists next to
the document, in which case that one is reused instead of creating
`assets` alongside it. No image on the clipboard leaves no folder behind
either way.

- **Tab:** true
- **Module:** `images/paste.lua` (`M.run`, `find_existing_resource_dir`,
  `sanitize_filename`)
- **Usercmds:** `:Image paste [name]` ([usercmds](../BINDINGS.md#user-commands))
- **Naming from a keymap (2026-08-24):** any count on `keymaps.paste` /
  `keymaps.screenshot` forces the filename prompt. `M.paste(name)` always
  accepted a name and `capture_with_optional_name` already prompted when
  `paste.ask_filename` was on — but with it off, a bare lhs had no way to
  supply one, so `:Image paste {name}` was the only route. The count's
  *value* is ignored on purpose: there is no meaningful "paste this 3 times",
  so it reads purely as a flag. Closes the flag/option audit's entry, which
  had called a name argument here "desirable but impractical as a bare-lhs
  keymap" — impractical as an argument, yes; as a prompt trigger, not.
- **Keymaps:** `<leader>iv` ([keymaps](../BINDINGS.md#keymaps))
- **Config:** `opts.paste.dir` (default `"assets"`),
  `opts.paste.existing_dir_names` (default `{"Resources", "Ressourcen"}`),
  `opts.paste.name_template`, `opts.paste.link_template`

### With a filename argument or prompt

`:Image paste {name}` sanitizes and uses `{name}` directly, skipping any
prompt — a name on the command line always takes priority over
`opts.paste.ask_filename`. With `ask_filename = true` and no argument, a
prompt asks for a name prefilled with what the template would have
produced; any path component typed in is dropped and the extension is
always forced to `.png`. Cancelling this prompt writes nothing at all,
since the clipboard hasn't been read yet — unlike the alt-text prompt
below, where the file is already on disk by the time you could cancel.

`opts.paste.ask_alt_text = true` prompts for alt text before inserting the
link, producing `![alt](path)` instead of `![](path)`. Cancelling here
still inserts the plain link — a lost link would be the worse surprise
once the file already exists on disk.

## Screenshot

Takes a screenshot interactively and continues exactly like paste,
skipping the "have something on the clipboard already" step. Uses
`screencapture -i` on macOS, `grim`+`slurp` or `maim -s` on Linux, and the
Windows Snipping Tool (`ms-screenclip:`) on Windows.

- **Module:** `images/screenshot.lua` (`M.capture`, `M.available`),
  `images/paste.lua` (`M.screenshot`)
- **Usercmds:** `:Image screenshot` ([usercmds](../BINDINGS.md#user-commands))
- **Keymaps:** `<leader>is` ([keymaps](../BINDINGS.md#keymaps))
- **Config:** `opts.display.screenshot.windows_timeout_ms` (default
  `60000`), `opts.display.screenshot.windows_poll_interval_ms` (default
  `600`)

Windows has no documented way to have the Snipping Tool write directly to
a file, so this path waits for a new image to appear on the clipboard
instead, polling until the timeout. `:Image paste` is the proven two-step
fallback if that polling doesn't work in a given environment.

## Replace

Overwrites an existing image file with the current clipboard image,
keeping the markdown link that already points at it unchanged.

- **Module:** `images/paste.lua` (`M.replace`)
- **Usercmds:** `:Image replace [path]` ([usercmds](../BINDINGS.md#user-commands))

## Export to PDF

Exports an image as a PDF next to the source file. Routes through
`pdfport.nvim`'s `create()` API when that plugin is installed
(asynchronous, lossless via `img2pdf` if available, else `magick`);
otherwise requires ImageMagick directly and runs synchronously.

- **Module:** `images/convert.lua` (`M.to_pdf`)
- **Usercmds:** `:Image export [path]` ([usercmds](../BINDINGS.md#user-commands))

## Redact

Opens a full-screen censor mode over an image: enter Visual mode
(`v`/`<C-v>`), move to the opposite corner of the area to black out,
`<CR>` marks the box — repeat for as many boxes as needed, `u` undoes the
last one, `w` burns every marked box in via ImageMagick and writes a new
file (`photo.png` → `photo.redacted.png`). The source file is never
touched.

- **Tab:** true
- **Module:** `images/redact.lua` (`M.open`, `confirm_box`, `undo_box`,
  `write_redacted`), `images/convert.lua` (`M.redact`)
- **Usercmds:** `:Image redact [path]` ([usercmds](../BINDINGS.md#user-commands))
- **Config:** `opts.display.redact.padding_cells` (default `1`)
- **Count (2026-08-24):** `u` removes the last box, `3u` removes three —
  clamped to what is actually there rather than warning once per missing box.
  Marking a run of boxes in the wrong place no longer means pressing `u`
  repeatedly and reading a notification each time.

### Why boxes are padded generously

Selection happens entirely in terminal cells — there is no pixel-precise
mouse input available in a terminal at all, so each marked box gets a
configurable safety margin (default one cell) added around it before
burning in. Over-redacting is the safe failure mode; under-redacting is
not. See `docs/ROADMAP/REDACT.md` for the fuller design rationale.

## Orphan cleanup

Scans `paste.dir` for image files that no link in the buffer points to
anymore, and offers to delete them one at a time.

- **Module:** `images/orphans.lua` (`M.find`), `images/init.lua`
  (`M.orphans`)
- **Usercmds:** `:Image orphans` ([usercmds](../BINDINGS.md#user-commands))

## Image metadata

Reports format, pixel dimensions and file size for an image. Dimensions
require ImageMagick; without it, only format and size are shown.

- **Module:** `images/info.lua` (`M.collect`, `M.human_size`, `M.lines`)
- **Usercmds:** `:Image info [path]` ([usercmds](../BINDINGS.md#user-commands))
