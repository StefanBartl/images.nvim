# BINDINGS — images.nvim

Cheatsheet of everything images.nvim registers.

## User commands

One verb built with `lib.nvim.usercmd.composer`, so dispatch, `<Tab>`
completion and this table all come from the same spec.

| Command | Range | Description |
| --- | --- | --- |
| `:Image` | — | Show the image under the cursor (bare form, no subcommand) |
| `:Image show [path]` | — | Show `path`; without an argument, the image under the cursor |
| `:Image list` | yes | Pick from the image links of the buffer |
| `:Image gallery [cols]` | — | Show every image of the buffer side by side in a grid |
| `:Image next` | — | Jump to the next image of the buffer and show it |
| `:Image prev` | — | Same, backwards; both wrap around |
| `:Image info [path]` | — | Format, dimensions and file size |
| `:Image paste` | — | Save the clipboard image next to the document and insert the link |
| `:Image pin` | — | Keep the image on screen instead of clearing on cursor move |
| `:Image check` | — | Report whether this terminal can display images |
| `:Image clear` | — | Remove displayed images and release a pin |

`:Image list` honours a visual range: `:'<,'>Image list` restricts the scan to
the selected lines. The other subcommands operate on a single position or the
whole buffer, where a range carries no meaning.

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
| `<2-LeftMouse>` | n | Double-click a markdown link to show the image | `keymaps.double_click` |

A double-click that does not land on an image link falls through to the normal
word selection, so the mapping never swallows a plain double-click.

## Autocmds

| Augroup | Event | Description |
| --- | --- | --- |
| images.keymaps | `FileType` | Registers the buffer-local keymaps |
| images.autocmds | `VimLeavePre` | Clears a displayed image before quitting |
| images.clear | `display.clear_events` | Clears the image after it was shown (`once`) |

The clear group is registered only while an image is on screen, not
permanently — it exists for the few seconds the image is visible, and
`:Image pin` removes it again.
