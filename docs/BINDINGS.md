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
| `:Image paste` | — | Save the clipboard image next to the document and insert the link |
| `:Image screenshot` | — | Take a screenshot interactively and insert the link — skips the clipboard step |
| `:Image replace [path]` | — | Overwrite an image with the clipboard, keep the link |
| `:Image export [path]` | — | Export an image as PDF next to the source file (needs ImageMagick) |
| `:Image redact [path]` | — | Censor mode: mark boxes (Visual + `<CR>`), `w` blacks them out into a new file (needs ImageMagick) |
| `:Image orphans` | — | Find images in `paste.dir` with no link, offer to delete one |
| `:Image pickers [cfile\|cwd\|path] [dir]` | — | Browse images under a scope, live preview with snacks.picker if installed |
| `:Image compare [cfile\|cwd\|path] [dir]` | — | Pick two images from a scan, view at true relative size (needs ImageMagick; else side by side, equal size) |
| `:Image zen [path]` | — | Show one image full-screen in a real editable window |
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
| `<leader>in` | n | Next image | `keymaps.next` |
| `<leader>ip` | n | Previous image | `keymaps.prev` |
| `<leader>iv` | n | Paste the clipboard image and insert the link | `keymaps.paste` |
| `<leader>is` | n | Take a screenshot and insert the link | `keymaps.screenshot` |
| `<2-LeftMouse>` | n | Double-click a markdown link to show the image | `keymaps.double_click` |

A double-click that does not land on an image link falls through to the normal
word selection, so the mapping never swallows a plain double-click.

## Autocmds

| Augroup | Event | Description |
| --- | --- | --- |
| images.keymaps | `FileType` | Registers the buffer-local keymaps |
| images.autocmds | `VimLeavePre` | Clears a displayed image before quitting |
| images.clear | `display.clear_events` | Clears the image after it was shown (`once`) |
| images.zen | `WinResized`, `VimResized` | Redraws the `:Image zen` image so it follows the window's size |
| images.zen | `WinClosed` | Clears the image when the zen window closes (`once`) |
| images.redact | `WinClosed` | Clears the image when the redact window closes (`once`) |

The clear group is registered only while an image is on screen, not
permanently — it exists for the few seconds the image is visible, and
`:Image pin` removes it again. The zen and redact groups are likewise
scoped to the lifetime of their own open window, re-created on each call.
