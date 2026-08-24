# BINDINGS — images.nvim

Cheatsheet of everything images.nvim registers.

## User commands

One verb built with `lib.nvim.usercmd.composer`, so dispatch, `<Tab>`
completion and this table all come from the same spec.

| Command | Range | Description |
| --- | --- | --- |
| `:Image` | yes | Show the image under the cursor; with a range, gallery of that range |
| `:Image show [path]` | — | Show `path` (or a URL if `display.remote.enabled`); without an argument, the image under the cursor |
| `:Image list` | yes | Pick from the image links of the buffer (or the range) |
| `:Image gallery [cols]` | yes | Show every image of the buffer (or the range) side by side |
| `:Image next` | — | Jump to the next image of the buffer and show it |
| `:Image prev` | — | Same, backwards; both wrap around |
| `:Image info [path]` | — | Format, dimensions and file size |
| `:Image paste [name]` | — | Save the clipboard image next to the document and insert the link; with `name`, use that filename directly |
| `:Image screenshot` | — | Take a screenshot interactively and insert the link — skips the clipboard step |
| `:Image replace [path]` | — | Overwrite an image with the clipboard, keep the link |
| `:Image export [path]` | — | Export an image as PDF next to the source file (via `pdfport.nvim` if installed, else needs ImageMagick) |
| `:Image redact [path]` | — | Censor mode: mark boxes (Visual + `<CR>`), `w` blacks them out into a new file (needs ImageMagick) |
| `:Image orphans` | — | Find images in `paste.dir` with no link, offer to delete one |
| `:Image calibrate` | — | Measure this terminal's image placement, store the correction |
| `:Image pickers [cfile\|cwd\|path] [dir]` | — | Browse images under a scope, live preview with snacks.picker if installed |
| `:Image compare [cfile\|cwd\|path] [dir]` | — | Pick two images from a scan, view at true relative size (needs ImageMagick; else side by side, equal size) |
| `:Image zen [path]` | — | Show one image full-screen in a real editable window |
| `:Image draw <position> [path]` | — | Draw an image at a named position in the current window (`full`/9 anchors); the primitive zen/hover/redact/the picker preview build on, also `images.draw()` |
| `:Image pin` | — | Keep the image on screen instead of clearing on cursor move |
| `:Image check` | — | Report whether this terminal can display images |
| `:Image clear` | — | Remove displayed images, release a pin, and close a `:Image zen` window |

`range = true` is set once at the verb level, not per route — the composer
only honours the first `range` value it finds across the whole spec, so a mix
would be misleading. `ctx.range.range > 0` distinguishes an actual
`:'<,'>Image …` call from a bare one, where `line1`/`line2` would otherwise
just point at the current line without that being the intent.

The command name is configurable via `command`.

## Keymaps

Registered per buffer for the filetypes in `keymaps.filetypes`
(default: `markdown`, `vimwiki`, `norg`, `text`). Every entry accepts `false`
to disable that single mapping.

| Key | Mode | Description | Option |
| --- | --- | --- | --- |
| `<leader>im` | n | Show the image under the cursor | `keymaps.show` |
| `<leader>ig` | n | Show all images of the buffer side by side | `keymaps.gallery` |
| `<leader>in` | n | Next image; `3<leader>in` jumps three | `keymaps.next` |
| `<leader>ip` | n | Previous image; a count jumps that many | `keymaps.prev` |
| `<leader>iv` | n | Paste the clipboard image and insert the link; **any count** prompts for a filename | `keymaps.paste` |
| `<leader>is` | n | Take a screenshot and insert the link; **any count** prompts for a filename | `keymaps.screenshot` |
| `<2-LeftMouse>` | n | Double-click a markdown link to show the image | `keymaps.double_click` |

### Counts (2026-08-24)

`next`/`prev` multiply the step: `step()` already wraps modulo the image
count, so `3<leader>in` lands three images on and wraps exactly as one step
would.

On `paste`/`screenshot` a count is not a repeat — it asks for a **name**.
`:Image paste {name}` could always supply one, but a bare lhs carries no
text, and with `paste.ask_filename = false` a keymap had no way to name the
file at all. Any count now forces the prompt; with `ask_filename` already on
this changes nothing. The count's *value* is deliberately ignored — there is
no sensible "do this 3 times" for pasting one image, so it reads purely as a
flag.

In the redact window, `u` removes the last box and `3u` removes three,
clamped to what is actually there rather than warning once per missing box.

A double-click that does not land on an image link falls through to the normal
word selection, so the mapping never swallows a plain double-click.

`<2-LeftMouse>` is only set when the buffer does not already have a
buffer-local mapping for it. markdown.nvim binds the same key on the same
filetypes and routes anchor → image → URL → file, delegating the image case
back to images.nvim; since both register from a `FileType` autocmd, load order
would otherwise decide the winner, and images.nvim winning would drop the
other cases. Whoever binds first keeps the key.

## Autocmds

| Augroup | Event | Description |
| --- | --- | --- |
| images.keymaps | `FileType` | Registers the buffer-local keymaps |
| images.autocmds | `VimLeavePre` | Clears a displayed image before quitting |
| images.clear | `display.clear_events` | Clears the image after it was shown (`once`) |
| images.zen | `WinResized`, `VimResized` | Redraws the `:Image zen` image so it follows the window's size |
| images.zen | `WinClosed` | Clears the image when the zen window closes (`once`) |
| images.redact | `WinClosed` | Clears the image when the redact window closes (`once`) |
| images.ascii | `WinClosed` | Clears the ASCII-fallback window state when it closes (`once`) |

The clear group is registered only while an image is on screen, not
permanently — it exists for the few seconds the image is visible, and
`:Image pin` removes it again. The zen and redact groups are likewise
scoped to the lifetime of their own open window, re-created on each call.
