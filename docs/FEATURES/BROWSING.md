# Browsing

Finding, stepping through and comparing images, whether the source is a
single buffer or a whole directory tree.

## List images in the buffer

Picks from every image link found in the buffer (or a visual range) and
shows the chosen one. Uses lib.nvim's UI kit picker when available, else
falls back to `vim.ui.select`.

- **Module:** `images/init.lua` (`M.list`), `images/scan.lua`
  (`M.buffer`)
- **Usercmds:** `:Image list`, `:'<,'>Image list` ([usercmds](../BINDINGS.md#user-commands))

## Gallery

Shows every image of the buffer (or a range) side by side in a grid, with
an automatically computed column count unless one is given explicitly.

- **Module:** `images/init.lua` (`M.gallery`, `M.gallery_range`),
  `images/gallery.lua` (`M.layout`, `auto_columns`)
- **Usercmds:** `:Image gallery [cols]`, `:'<,'>Image` (range with no
  subcommand) ([usercmds](../BINDINGS.md#user-commands))
- **Keymaps:** `<leader>ig` ([keymaps](../BINDINGS.md#keymaps))
- **Config:** `opts.display.gallery_gap` (cells between tiles, default
  `1`)

## Next / previous

Jumps to the next or previous image link in the buffer and shows it; both
directions wrap around.

- **Module:** `images/init.lua` (`M.step`)
- **Usercmds:** `:Image next`, `:Image prev` ([usercmds](../BINDINGS.md#user-commands))
- **Keymaps:** `<leader>in`, `<leader>ip` ([keymaps](../BINDINGS.md#keymaps))

## Directory pickers

Browses images under `cfile`, `cwd`, or an explicit path, with a live
thumbnail preview when snacks.picker is installed (a custom preview
function, not snacks.image's Kitty-only one), falling back to a plain
list without preview otherwise. `<Tab>` multi-selects in the snacks
picker; confirming a multi-selection shows the chosen images as a gallery
instead of one image.

- **Module:** `images/browse.lua` (`M.open`, `M.scan`, `M.roots`,
  `M.snacks_available`)
- **Usercmds:** `:Image pickers [cfile|cwd|path] [dir]` ([usercmds](../BINDINGS.md#user-commands))
- **Config:** `opts.display.browse_exclude` (directories skipped besides
  the always-excluded `.git`, default `{".deps", "node_modules"}`)

## Compare

Picks two images from a directory scan and shows them side by side. With
ImageMagick installed, they're scaled proportionally to their true
relative size, so a small icon and a large photo don't render at the same
size; without it, both are shown side by side at equal size.

- **Module:** `images/compare.lua` (`M.open`)
- **Usercmds:** `:Image compare [cfile|cwd|path] [dir]` ([usercmds](../BINDINGS.md#user-commands))

## Clear

Removes any displayed image, releases a pin, and closes a `:Image zen`
window if one is open.

- **Module:** `images/init.lua` (`M.clear`)
- **Usercmds:** `:Image clear` ([usercmds](../BINDINGS.md#user-commands))
