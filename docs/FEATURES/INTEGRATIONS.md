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

## gopath.nvim plain-path resolution

`images.resolve.under_cursor()` tries, in order: a Markdown link, a
`<figure>`/`<figcaption>` block (markdown.nvim only), then gopath.nvim's
cursor resolver, before falling back to Vim's own `<cfile>`. Only a result
gopath confirms exists on disk is accepted, and only when its extension is
one of `opts.extensions` — neither an LSP/treesitter symbol gopath might
otherwise resolve to nor a typo offering a "create this file?" prompt has
any business surfacing from `:Image show`.

**What this does and does not buy, measured.** Toggling
`display.gopath_fallback` resolves the same files either way for ordinary
paths: `to_path` already tries markdown.nvim's resolver, the buffer's own
directory, then the cwd. What gopath adds on top is its harder cases — a
truncated path (`...nvim/init.lua`), a `:line:col` suffix, a file findable
only through `&path`/rtp/a tail search. Worth having for `:Image show` on
whatever the cursor happens to be on; not the thing that makes a bare path
*hover*.

**The hover itself is lib.nvim's**, and images.nvim is one provider inside
it — `lib.nvim.hover.preview.media` calls `images.info` and
`images.scale.fit_cells` to draw the picture, the same way it calls
`pdfport.render_page` for a PDF page. Bare paths (and truncated ones out of
`:messages`) hover through `lib.nvim.hover.bare_path`, in every filetype.
The framework deliberately stays there rather than moving here.

It began in markdown.nvim, which is why older notes here name
`markdown.hover.*`. Almost none of it turned out to be about markdown, and
moving it into *this* plugin instead would have been the same mistake wearing
different clothes: images.nvim draws pictures, and would then have owned
directory listings, file heads and URL fetching. markdown.nvim still
contributes its link scanning and `#heading` previews, through the hover's
registry rather than by owning it.

The float is lib.nvim's window, not one of ours, so its keys are documented
there: `q` / `<Esc>` dismiss it (and keep it dismissed while the cursor stays
on that target), `<M-PageDown>` / `<C-Down>` page a scrollable preview, and
`:Lib hover toggle` switches the feature off for a session. **Not to be
confused with this plugin's own hover** — `display.hover_mode`,
`images.hover_float` — which is a separate feature with its own window and
its own keys; see [DISPLAY.md](DISPLAY.md#hover-overlay--hover-float).

- **Module:** `images/resolve.lua` (`resolve_via_gopath`, internal to
  `under_cursor`)
- **Config:** `display.gopath_fallback` (default `true`)
- **Dependency:** gopath.nvim, soft and `pcall`'d — `<cfile>` remains the
  fallback without it, unchanged from before this integration existed

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

- **Module:** `images/browse.lua` (`draw_in_window`)
- **Usercmds:** `:Image pickers`
- **Dependency:** snacks.nvim, soft — the list still works without it

## filetree.nvim and open.nvim

`filetree.nvim` uses images.nvim as the first backend of its own preview
feature, and `open.nvim` routes `:Open image` here.

- **Module:** `images/init.lua` (`draw`) — the entry point both call
- **Dependency:** none here; the relationship runs from those plugins to this one

## pdfport.nvim for export

`:Image export` routes through `pdfport.nvim`'s `create()` API when that
plugin is installed (asynchronous, lossless via `img2pdf` if available,
otherwise `magick` through pdfport's own fallback chain). Soft dependency,
`pcall`'d — without pdfport.nvim, the previous synchronous
ImageMagick-only export path is unchanged.

- **Module:** `images/convert.lua`
- **Usercmds:** `:Image export`
- **Dependency:** pdfport.nvim, soft and `pcall`'d — falls back to the synchronous ImageMagick path

## language.nvim after OCR — an integration with no code in it

`:Image ocr` puts the recognised text into a `markdown` scratch buffer, and
that is the whole integration: `language.nvim`'s spell checking attaches to
the buffer on its own, and every public entry point of `language.translate`
is buffer-bound (`run_region` wants a `bufnr` plus coordinates), so
selecting a paragraph and running `:Translate` needs nothing from this
plugin.

Worth stating explicitly because the roadmap entry that asked for this
described a bridge between two plugins, and building one would have been
wasted work — with a worse result, since a bespoke bridge would have
supported whichever subset of `:Translate`'s flags someone thought to wire
up, instead of all of them.

- **Module:** `images/ocr.lua`, `images/init.lua` (`M.ocr`)
- **Usercmds:** `:Image ocr [path] [--lang=<code>]`, then `:Translate` /
  `:Spellcheck` from language.nvim
- **Dependency:** none. language.nvim is not required, not `pcall`'d, not
  referenced — the two meet in a buffer, not in an API.

## lib.nvim.deps: missing-tool reporting

ImageMagick, `tesseract` and `chafa` are declared as optional dependencies,
with the reasoning per tool, in `docs/install.json`, parsed by lib.nvim's
`deps` module. The first time `setup()` runs after installing images.nvim, a
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
