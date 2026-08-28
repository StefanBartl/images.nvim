# CROSS-PLUGIN — cross-cutting features with the other repos

A pass through every `*.nvim` repo in `E:\repos` asking where image display
brings real benefit. Sorted by how well the idea holds up, not alphabetically.
Plugins with no meaningful connection sit at the end — with reasons, so the
question is not reopened on every pass.

A principle throughout: images.nvim is a **soft dependency** everywhere, via
`pcall`. Without it the caller falls back to its previous behaviour. No repo
gains a hard dependency on image display.

---

## Strong — concrete benefit, manageable effort

### `color_my_ascii.nvim` — IMPLEMENTED, but not the way it was conceived here
The reverse direction: render an image **as ASCII art** when the terminal
cannot do OSC 1337 — the universal fallback for any terminal without a
graphics protocol, which makes the plugin usable over SSH and in tmux (without
passthrough) too.

Implemented in `images.ascii` (`display.ascii_fallback`), **without** the
color_my_ascii dependency conceived here: color_my_ascii colours known ASCII
character classes (arrows, box drawing, …) against a named scheme,
pattern-based, one colour per class — but real image colours need an arbitrary
RGB colour per cell, derived from the pixels themselves. That is a different
kind of colouring, one color_my_ascii does not offer architecturally and does
not intend to (it is a syntax highlighter for text, not an image renderer).
`images.ascii` therefore goes straight through `nvim_set_hl`/extmarks:
ImageMagick downsamples the image to the target cell count (`-resize WxH!
-alpha off -depth 8 RGB:-`), and every cell becomes a "█" with its own
foreground colour — truecolour block graphics as in chafa/viu, not a brightness
character ramp. Requires ImageMagick (the fourth exception alongside
SVG/export/redact). So far the single-image path only (`:Image show`/hover), as
with remote images.

### `markdown.nvim` — IMPLEMENTED
Its path resolver is already in use. Implemented in the other direction too:
`:Markdown links show` now shows image links with a live preview (via
`snacks.picker` + `images.browse.draw_in_window` — the same function `:Image
pickers` itself uses for its preview, so no new API work here); `:Markdown
image paste|screenshot` delegates straight to `:Image paste`/`:Image
screenshot`.

**An incidental finding:** `markdown.nvim` already had its own in-Neovim
preview path for `mi` (open the image under the cursor) — but through
snacks.nvim/image.nvim, the same Kitty-only plugins that never draw on this
Windows/WezTerm setup. images.nvim is now wired in there as the preferred third
provider (`markdown.util.image_preview`), with snacks/image.nvim remaining the
fallback for setups where those actually work.

### `gopath.nvim` — IMPLEMENTED, but read the role split below first
The observation that started this: the cursor resting on
`docs/assets/screenshot.png` written as bare text (no `![alt](...)`) produced
no preview, in any buffer.

**Implemented here: images.nvim → gopath.nvim, for the cursor target.**
`images.resolve.under_cursor()` asks gopath's `resolve_at_cursor()` (soft
dependency, `display.gopath_fallback`) as a fourth source, after Markdown
links and `<figure>` blocks and before the old `<cfile>` fallback. Only a
result gopath *confirms exists*, with an extension in `opts.extensions`, is
accepted — an unconfirmed guess or an LSP/treesitter symbol gopath resolved
for an unrelated reason never reaches `:Image show`. Details:
`docs/FEATURES/INTEGRATIONS.md#gopathnvim-plain-path-resolution`.

**What this is NOT, measured rather than assumed.** It is not what makes bare
paths hover. Toggling `display.gopath_fallback` off and on resolves the same
files either way: `images.resolve.to_path` already tries markdown.nvim's
resolver, then the buffer's directory, then the cwd, which covers ordinary
relative and absolute paths on its own. What this adds is only gopath's
harder cases — a truncated path, a `:line:col` suffix, a file findable solely
through `&path`/rtp/a tail search. Useful for `:Image show` under the cursor;
not the feature it was first written up as.

**The hover itself lives in markdown.nvim, and should stay there.** Its
`markdown.hover` is a ~1600-line preview framework — `classify` (image, PDF,
markdown, file, directory, url, anchor, missing), `float`, `preview/text`
(file head, directory listing, `#anchor` section), `preview/url`, plus
debounce, an LRU cache and a generation counter for async results. In it,
**images.nvim is one provider**: `preview/media` calls `images.info` and
`images.scale.fit_cells` to draw a picture, exactly as it calls
`pdfport.render_page` to rasterize a PDF page. `markdown.hover.bare_path`
(added there, using gopath the same way) is what actually made bare paths and
`:messages` paths hover, in every filetype.

Moving that framework here was considered and rejected: images.nvim can draw
images and nothing else, so it would have to duplicate ~1200 lines of text /
directory / URL / float handling, or call back into markdown.nvim to list a
directory — a worse arrangement than being its picture provider. The framework
is admittedly generic enough that `lib.nvim` would be its natural home; that
move is a real option, not a prerequisite, and nothing about the current split
is wrong while it stays put.

**Deliberately not built in the same pass: gopath.nvim → images.nvim, for the
`open` action.** `gopath.external.pdf` already has exactly the shape this
would need — a mode chooser ("System app" first, soft dependency, `pcall`'d,
config `picker`/`default`, opt-out even when the dependency is installed) — an
`images.lua` module mirroring `pdf.lua` almost line for line would let
gopath's `gF`-style open show an image inline via `images.show`/`images.zen`
instead of always launching the system viewer. Held back for now because it is
a genuinely separate feature (a deliberate "open" action, not the passive
hover the first direction extends) with its own scope in a different repo, not
because of any doubt about the design — the template is proven, this is next
whenever gopath.nvim work resumes.

**Why not one soft dependency covering both directions.** They query
different things for different triggers (a read-only "what's under the
cursor" during a hover vs. a render call during a deliberate open) and never
call into each other, so nothing about them is actually shared — building one
generic bridge module for both would only add an indirection neither
direction needs.

### `mdview.nvim` — IMPLEMENTED, but the real gap was a different one
A markdown preview without images is half a preview. Collect the image links
while rendering and draw them in the right places.

On investigation it turned out that mdview renders completely differently from
images.nvim — no terminal overlay but a real browser tab, via a Go relay plus a
Rust/WASM renderer (`comrak`). The WASM renderer had always produced correct
`<img>` HTML for `![alt](image.png)` (evidenced by an existing, passing test) —
so "collect the image links and draw them" was never the gap. The real gap: the
relay's only `http.FileServer` pointed at the client bundle, never at the
directory of the document currently displayed, so a relative image path led
nowhere server-side — a broken image icon in the browser despite correct HTML.

A new, token-authenticated `GET /asset` route in the Go relay, resolved
relative to a directory that comes exclusively from the trusted local Neovim
process (never from the browser tab), with path traversal protection and an
image extension allowlist. Client-side, `resolveLocalImages` rewrites relative
`<img src>` onto that route after every render. Details and tests:
`mdview.nvim/docs/architecture.md` ("Local image assets"),
`docs/Roadmap/Roadmap.md`.

### `pickers.nvim`
**Examined and deliberately not built this way.** `:Image pickers`/`:Image
compare` bind directly to `snacks.picker` instead (a soft dependency, see
`images.browse`'s module docs): `pickers.nvim`'s engine abstraction unifies
telescope/fzf-lua/snacks, but has no engine-spanning way to put a preview of
one's own across all three — only snacks allows a custom `preview` function per
picker, and that live preview is the whole point of the feature. Without snacks
`images.browse` falls back to a plain selection with no preview, rather than
faking through `pickers.nvim` a preview that cannot exist there.

### `insights.nvim` — IMPLEMENTED, scoped more narrowly than first conceived
Project analysis produces graphs — dependencies, call trees, symbol
distribution. Rendered through Graphviz to PNG and shown inline, rather than
forcing a text-tree representation.

On investigation it turned out that only the import/require data
(`insights.imports`) is actually graph-shaped already — every entry is a edge
("file imports module"), merely never drawn as a graph. Call trees and symbol
distribution exist as data nowhere in insights.nvim (`symbols` is a flat,
uncorrelated list) — that would be a new and considerably larger analysis
capability, not a new view onto something existing. Hence deliberately the
dependency graph only: `:Insights imports graph` (`insights.imports.graph`), a
Graphviz `digraph` through `dot -Tpng`, with external modules hidden by default
(`imports.graph.include_external`, otherwise more noise than structure), shown
through `images.nvim` (a soft dependency).

`documentation.nvim`'s `:DocMap` output remains open — its own repo, its own
scope, not part of this pass.

### `diff.nvim` — IMPLEMENTED
Image diff: two image versions side by side, with shared scaling. The gallery
layout already exists; `diff.nvim` would only have to recognise that both sides
are images and call the display instead of a text diff.

`diff.core.resolve` used to read every file unconditionally as text via
`vim.fn.readfile` — for two image files that meant a meaningless byte "diff",
not even an error. `lua/diff/features/image_compare.lua` catches exactly that
case: both sides readable raster image paths (SVG deliberately excluded, that
is text and diffs sensibly as text) -> `images.gallery({a, b}, 2)` instead of a
text diff. Without images.nvim installed, a clear warning rather than the
previous silent nonsense. **No relative scaling** as in `:Image compare` — that
would need `lib.nvim.ui.kit.compare`'s scan-and-select flow to know both images
at once, which does not fit here: `:Diff` already has both concrete paths from
its own arguments, so `images.gallery` is the right, already existing primitive
— no new API work needed in images.nvim.

That completes this pass through the "strong" list.

---

## Medium — sensible, but with open questions

### `language.nvim`
OCR on an image, to extract text and then translate or check it. For
screenshots of error messages in foreign-language systems, a real support case.

**Decided:** `tesseract` is assumed to be present (Windows included) — an
improvement, not a prerequisite, the same stance as for ImageMagick elsewhere
in the plugin. Without it, either a fallback chain applies or the feature is
simply not offered, whichever makes more sense while building — no longer an
open question, just an implementation detail.

### `runtime-analysis.nvim`
Flamegraphs as an image rather than a text tree. In 60x25 terminal cells
probably only a rough overview — but the image lands on disk as an ordinary
file anyway and can be viewed at full resolution in a browser, with
`mdview.nvim` or any other image application, so with zoom (see FEATURES.md) it
remains a genuine gain rather than merely a terminal crutch.

**Added:** the same graphic belongs in `documentation.nvim` too — there is
already a section there for data from `runtime-analysis.nvim` that currently
shows only text.

### `github_stats.nvim`
Render statistics as a chart rather than a column of numbers. Presupposes a
chart renderer that does not exist anywhere yet — the effort lies there, not in
the display.

### `fileops.nvim`
Image operations as file operations: convert, scale, optimise. Fits the "one
command, all operations" theme.

**Decided:** ImageMagick is assumed to be present, as with `tesseract` above —
without it, a fallback chain or disable the feature.

---

## Rejected — examined, deliberately not implemented

### `sessions.nvim`
Keep pinned images across a session switch.

**Decided: do not implement.** Only worthwhile when several images can be
pinned at once — the state does not justify persisting otherwise.

### `buffer-ctx.nvim`
An image link as the same insertion action as paths/modules/timestamps/UUIDs.

**Decided: do not implement.** `:Image paste` already covers the case; a shared
insertion mechanism would not be a new capability.

### `migrate.nvim`
An image preview instead of binary noise in the telescope preview, when a
migration step touches image files.

**Decided: do not implement.** A pure edge case.

---

## Open — needs a trial run before deciding

### `reposcope.nvim`
When previewing a GitHub repo, show its social preview card or the README
images. Nice, but the benefit is small against the network cost — and it needs
remote images (see FEATURES.md).

**Next step:** a trial run of how much this actually harms `:Reposcope`'s
snappiness, before building — no decision yet.

---

## No meaningful connection

For completeness, so the question stays settled:

`cmdlog.nvim` (command history), `emojis.nvim` (character picker),
`recommender.nvim` (repetition analysis), `replacer.nvim` (search/replace),
`spotlight.nvim` (tokens in logs),
`sandbox.nvim` (container TUI), `cascade.nvim` (line scan/scope), `lsp.nvim`
and `dap.nvim`/`debugging.nvim` (language and debug tooling). `migrate.nvim`,
`sessions.nvim` and `buffer-ctx.nvim` appear with reasons under "Rejected"
above.

For `dap.nvim`/`debugging.nvim` the most one could imagine is storing a
screenshot of the debug state for a bug report — but that is `:Image paste` and
needs no integration.

---

## `lib.nvim`

Not a cross-cutting feature but the question of what belongs upstream.
Candidates:

- **Terminal capability detection** — which graphics protocol can this terminal
  do? That concerns every plugin wanting to output anything other than text,
  and today it is scattered through `images.health`.
- **The OSC 1337 sequence itself**, should a second plugin need it directly
  (`mdview.nvim` would be the first candidate). While only images.nvim draws,
  it is better off here — moving it into lib.nvim without a second consumer
  creates a dependency with nothing in return.
- **The grid layout from `gallery.lua`** is already generic (pure arithmetic
  with no terminal involvement) and overlaps with `lib.nvim.ui.kit.layout`.
  Before moving it, check whether `layout.compute` does not already cover the
  case, and implement it there if so.
