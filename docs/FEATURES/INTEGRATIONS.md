# Integrations

How images.nvim connects to its sibling plugins and to optional external
tools.

## markdown.nvim link resolution

Link targets are resolved through `markdown.nvim` when present, falling
back to an internal resolver otherwise — a soft dependency, never
required. The relationship runs the other way too: `markdown.nvim`'s `mi`
prefers images.nvim as its in-Neovim preview provider over
Kitty-only plugins, and its `:Markdown links show` reuses
`images.browse.draw_in_window()` (a thin wrapper around `images.draw()`)
for a live per-item image preview when snacks.picker is also installed.

- **Module:** `images/resolve.lua` (`M.to_path`), `images/browse.lua`
  (`draw_in_window`)

## lib.nvim command grammar and picker

`lib.nvim` provides the `:Image` command grammar via
`usercmd.composer` (dispatch and `<Tab>` completion come from the same
spec that generates `docs/BINDINGS.md`), the picker used by `:Image
list`, and the `kit.compare` component behind `:Image compare`. Without
lib.nvim's UI kit, pickers fall back to `vim.ui.select`.

- **Config:** `opts.command` (default `"Image"`)

## snacks.picker previews

A soft dependency for `:Image pickers`: with snacks.nvim installed,
browsing shows a live image thumbnail per entry using a custom preview
function; without it, `:Image pickers` falls back to a plain list with no
preview.

## filetree.nvim and open.nvim

`filetree.nvim` uses images.nvim as the first backend of its own preview
feature, and `open.nvim` routes `:Open image` here.

## pdfport.nvim for export

`:Image export` routes through `pdfport.nvim`'s `create()` API when that
plugin is installed (asynchronous, lossless via `img2pdf` if available,
otherwise `magick` through pdfport's own fallback chain). Soft dependency,
`pcall`'d — without pdfport.nvim, the previous synchronous
ImageMagick-only export path is unchanged.

## lib.nvim.deps: missing-tool reporting

ImageMagick and `chafa` are declared as optional dependencies, with the
reasoning per tool, in `docs/install.json`, parsed by lib.nvim's `deps`
module. The first time `setup()` runs after installing images.nvim, a
popup shows what's missing and why, once ever.

- **Module:** `lua/images/health.lua` (`check_deps`, `check_lib_deps`)
- **Usercmds:** `:Lib deps show images.nvim`, `:Lib deps install
  images.nvim` (provided by lib.nvim, not this plugin)
- **Config:** `opts.deps_popup` (default `true`),
  `vim.g.lib_nvim_deps_disable_first_run`,
  `vim.g.lib_nvim_deps_disabled_plugins`

## Right-click context menu (nvzone/menu)

`images.integrations.menu` contributes entries — Show image under cursor,
Gallery, Next/Previous image, Paste from clipboard, Screenshot, Show image
info — in the shape [nvzone/menu](https://github.com/nvzone/menu) expects,
gated the same way the keymaps in `images.bindings.keymaps` are:
`keymaps.filetypes` (default markdown/vimwiki/norg/text) and
`config.menu.enable`. Mouse interaction is already a first-class idiom
here (`<2-LeftMouse>` hover) — this is a natural extension of it, not a new
one. images.nvim has no dependency on `menu` and never opens a context
menu itself; a host (typically your own `<RightMouse>` dispatcher)
composes the entries into its own menu.

- **Module:** `images/integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `opts.menu.enable` (default `true`)

## Health check

`:checkhealth images` verifies terminal capability, clipboard tool,
screenshot tool availability, ImageMagick, and both this plugin's and
lib.nvim's declared dependencies in one report.

- **Module:** `images/health.lua` (`M.check`)
