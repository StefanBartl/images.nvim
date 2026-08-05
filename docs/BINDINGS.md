# BINDINGS — images.nvim

Cheatsheet of everything images.nvim registers.

## User commands

| Command | Range | Description |
| --- | --- | --- |
| `:Image` | — | Show the image under the cursor (bare form, no subcommand) |
| `:Image show [path]` | — | Show `path`; without an argument, the image under the cursor |
| `:Image list` | yes | List image links in the buffer and pick one to show |
| `:Image paste` | — | Save the clipboard image next to the document and insert the link |
| `:Image clear` | — | Remove a displayed image |

`:Image list` honours a visual range: `:'<,'>Image list` restricts the scan to
the selected lines. The other subcommands operate on a single position or the
whole buffer, where a range carries no meaning.

The command name is configurable via `command`.

## Keymaps

Registered per buffer for the filetypes in `keymaps.filetypes`
(default: `markdown`, `vimwiki`, `norg`, `text`).

| Key | Mode | Description | Option |
| --- | --- | --- | --- |
| `<leader>im` | n | Show the image under the cursor | `keymaps.show` (`false` disables) |
| `<2-LeftMouse>` | n | Double-click a markdown link to show the image | `keymaps.double_click` |

A double-click that does not land on an image link falls through to the normal
word selection, so the mapping never swallows a plain double-click.

## Autocmds

| Group | Event | Description |
| --- | --- | --- |
| `images.keymaps` | `FileType` | Registers the buffer-local keymaps |
| `images.autocmds` | `VimLeavePre` | Clears a displayed image before quitting |
| `images.clear` | `keymaps.clear_events` | Clears the image after it was shown (`once`) |

The clear group is registered only while an image is on screen, not
permanently — it exists for the few seconds the image is visible.
