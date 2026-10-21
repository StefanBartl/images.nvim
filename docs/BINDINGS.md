# BINDINGS — images.nvim

Cheatsheet of everything images.nvim registers.

## User commands

One verb built with `lib.nvim.bindings.usercmd.composer`, so dispatch, `<Tab>`
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
| `:Image paste [env\|abs\|rel\|repos] [name] [path=<mode>\|<prefix>]` | — | Save the clipboard image next to the document and insert the link, then put the cursor into the link's empty alt text in insert mode; with `name`, use that filename directly; the mode word (or `path=`) picks how the link spells out the location (`env` = rooted at `$NVIM_CONFIG_DIR`/`$REPOS_DIR`/your own variables; default `paste.default_path_mode`, `"relative"`) |
| `:Image screenshot` | — | Take a screenshot interactively and insert the link — skips the clipboard step |
| `:Image replace [path]` | — | Overwrite an image with the clipboard, keep the link |
| `:Image export [path]` | — | Export an image as PDF next to the source file (via `pdfport.nvim` if installed, else needs ImageMagick) |
| `:Image redact [path]` | — | Censor mode: mark boxes (Visual + `<CR>`), `w` blacks them out into a new file (needs ImageMagick) |
| `:Image ocr [path] [--lang=<code>]` | — | Read the text out of an image into a markdown scratch split (needs `tesseract`); `--lang`/`-l` overrides `ocr.lang` |
| `:Image scale <size> [path]` | — | Resized copy next to the source (`photo.png` → `photo.scaled.png`); `size` is `50%`, `800x600`, `800x`, `x600` or `800x600!` (needs ImageMagick) |
| `:Image optimise [path] [--quality=<n>]` | — | Smaller copy next to the source (`photo.png` → `photo.optimised.png`): metadata stripped, best compression. A result that is not smaller is deleted and reported (needs ImageMagick) |
| `:Image convert <format> [path]` | — | Copy in another format, same stem (`photo.jpg` → `photo.png`); `pdf` takes the same route as `:Image export` (needs ImageMagick) |
| `:Image orphans` | — | Find images in `paste.dir` with no link, offer to delete one |
| `:Image calibrate` | — | Measure this terminal's image placement, store the correction |
| `:Image debug <mode> [path]` | — | Measure a misplaced draw: `report` logs the coordinates sent, `columns` tells a constant offset from a scaling one, `float` checks whether a window is where Neovim says it is, `disarm` undoes `report`'s instrumentation |
| `:Image pickers [cfile\|cwd\|path] [dir]` | — | Browse images under a scope, live preview with snacks.picker if installed |
| `:Image compare [cfile\|cwd\|path] [dir]` | — | Pick two images from a scan, view at true relative size (needs ImageMagick; else side by side, equal size) |
| `:Image zen [path]` | — | Show one image full-screen in a real editable window; inside it, zoom, move and resize with the [zen window keys](#zen-window) |
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

### Counts

`next`/`prev` multiply the step: `step()` wraps modulo the image count, so
`3<leader>in` lands three images on and wraps exactly as one step would.

On `paste`/`screenshot` a count is not a repeat — it asks for a **name**. A
bare lhs carries no text, so with `paste.ask_filename = false` a keymap would
otherwise have no way to name the file at all; any count forces the prompt,
and with `ask_filename` already on it changes nothing. The count's *value* is
deliberately ignored: there is no sensible "do this 3 times" for pasting one
image, so it reads purely as a flag.

In the redact window, `u` removes the last box and `3u` removes three,
clamped to what is actually there rather than warning once per missing box.

### Two things the double-click does not do

A double-click that does not land on an image link falls through to the normal
word selection, so the mapping never swallows a plain double-click.

`<2-LeftMouse>` is only set when the buffer does not already have a
buffer-local mapping for it. markdown.nvim binds the same key on the same
filetypes and routes anchor → image → URL → file, delegating the image case
back to images.nvim; since both register from a `FileType` autocmd, load order
would otherwise decide the winner, and images.nvim winning would drop the
other cases. Whoever binds first keeps the key.

### Zen window

Bound only in the `:Image zen` window's own buffer (also the window filetree.nvim
opens with `<CR>` on an image), through the same keymap registry under the
surface `images/zen`. Each one is set in `display.zen.keys`, accepts a list of
keys, and `false` drops it. A host can open a plain window with
`images.zen(path, { viewport = false })`: only its size, `?` and closing are
bound then (filetree.nvim's `preview.image.float.viewport = false`).

| Key | Description | Option |
| --- | --- | --- |
| `+` | Zoom in one step (1.5×) around the centre; `3+` three steps | `zoom_in` |
| `-` | Zoom out one step | `zoom_out` |
| `0`, `=` | Back to the whole picture | `zoom_reset` |
| `h` `j` `k` `l`, arrows | Move the visible part by a quarter of it; a count multiplies | `pan_left` `pan_down` `pan_up` `pan_right` |
| `H` `J` `K` `L` | Move it to that edge | `edge_left` `edge_down` `edge_up` `edge_right` |
| `<S-Up>` / `<S-Down>` | Grow / shrink the **window** through `display.zen.sizes` | `grow` / `shrink` |
| `<M-ScrollWheelUp>` / `<M-ScrollWheelDown>` | Alt + wheel: zoom in / out around the picture point under the pointer (only when the pointer is over the window) | `wheel_in` / `wheel_out` |
| `<MiddleMouse>` held + drag | Move the picture with the pointer, cell for cell; `<MiddleDrag>`/`<MiddleRelease>` follow from the key (`<M-LeftMouse>` brings `<M-LeftDrag>`/`<M-LeftRelease>`) | `drag` |
| `<LeftMouse>` held + drag, release | Select a part; on release it opens in a zen window of its own, stacked on this one (a click selects nothing) | `select_drag` |
| `v`, then `h` `j` `k` `l` / `H` `J` `K` `L`, `<CR>` | Select a part by keyboard: both corners start in the middle, the keys move the second corner (one / five cells), `<CR>` opens it | `select` |
| `<BS>` | From a selection back to the window it was cut from | `back` |
| `gs` | Save what is shown as a PNG next to the original: `shot.crop-<x>-<y>-<w>x<h>.png` (pixels of the original), `-2`, `-3` … rather than overwriting; nothing for the whole original | `save` |
| `gy` | Copy what is shown to the clipboard as an image (Windows drops transparency) | `yank` |

Saving cuts into the cache and moves the file into place last, looking again
first: two quick saves get two files, and a file that appeared under the name
meanwhile is never replaced (a generated name moves on to the next number, a
typed one is refused). A typed name is taken literally (`$`, `*` stay) except a
leading `~`, and a relative one lands next to the original. Zoom, selections and
saves of an animated GIF use its first frame.
| `?` | List the keys bound in this window; `?`, `q` or `<Esc>` close the list | `help` |
| `<Esc>` | Drop a selection in progress; otherwise close | — |
| `q` | Close — the whole stack of selections with it | — |

**Selecting never paints over the picture.** WezTerm drops the whole image as
soon as Neovim writes a cell inside it, so there is no visual mode and no
highlight: while you select, the frame takes the `ImagesZenSelect` colour
(links to `DiagnosticWarn`) and the command line says
`selection 640×360 px at 120,80` — in pixels of the original. The part is cut
from the **original** file at full resolution, also from a selection of a
selection, so cutting deeper loses nothing. The window it came from is hidden
and keeps its zoom; the title shows the depth (`shot.png · 2/2`). A press
beside the picture goes to Neovim as usual (focus, visual selection there).

The frame says where you are: the title carries the zoom factor
(`shot.png · 2.3×`, nothing at the whole picture), the footer `? help` points
at the list (just `?` in a window under 30 columns). The footer names whatever
`help` is bound to (`g? help` after `keys.help = "g?"`), that key also closes
the list, and with `help = false` there is no footer. The list is built from
what is actually bound, so a remapped key shows its new key and a disabled one
is absent. While it is open the picture is taken off the screen and drawn again
when it closes — a terminal image would otherwise sit on top of the list.
`display.zen.legend = false` keeps the frame to the file name.

The mouse keys need `'mouse'` to include normal mode (`:checkhealth images`
says when it does not). Alt rather than Ctrl for the wheel: `<C-ScrollWheel>`
is the terminal's own font zoom nearly everywhere.

Zoom shows *part* of the picture and is not the same as grow/shrink, which
change the window. It needs ImageMagick (each new view is a `magick` crop,
~250 ms for a 1080p screenshot) and an image whose header gives its size;
without either, the zoom keys say so once and change nothing. Views already
seen are cached, so stepping back is instant; while a crop runs, further key
presses only move the target, and the view you have arrived at is the one cut
next.

### which-key

With [which-key](https://github.com/folke/which-key.nvim) installed, the
longest common prefix of the configured keys (`<leader>i` by default) is
registered as a named group — computed from whatever `keymaps` actually
resolve to, so a fully remapped set still groups correctly. Skipped when fewer
than two keys share a prefix, or when the prefix would itself equal one of the
mapped keys, which would show an action and a group under the same key.

## Autocmds

| Augroup | Event | Description |
| --- | --- | --- |
| images.keymaps | `FileType` | Registers the buffer-local keymaps |
| images.autocmds | `VimLeavePre` | Clears a displayed image before quitting |
| images.clear | `display.clear_events` | Clears the image after it was shown (`once`) |
| images.zen | `WinResized`, `VimResized` | Redraws the `:Image zen` image so it follows the window's size |
| images.zen | `WinClosed` | Clears the image when the zen window closes (`once`) |
| images.hover_float | `WinClosed` | Clears the image and resets state when the hover float closes (`once`) |
| images.redact | `WinClosed` | Clears the image when the redact window closes (`once`) |
| images.ascii | `WinClosed` | Clears the ASCII-fallback window state when it closes (`once`) |

The clear group is registered only while an image is on screen, not
permanently — it exists for the few seconds the image is visible, and
`:Image pin` removes it again. The zen and redact groups are likewise
scoped to the lifetime of their own open window, re-created on each call.
