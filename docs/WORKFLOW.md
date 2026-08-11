# Workflow — using images.nvim day to day

Every command and option here is documented on its own in
`docs/FEATURES/` and `docs/BINDINGS.md`. This is the different question:
once you're actually writing markdown with images in it, which commands
do you reach for in sequence, and where does the plugin's terminal-first
design actually bite you if you don't know about it.

## The everyday loop: screenshot, not paste

`<leader>iv` (`:Image paste`) is the documented fallback, but
`<leader>is` (`:Image screenshot`) is the one worth building the muscle
memory for — it collapses "take a screenshot with the OS tool, switch
back to Neovim, then paste" into one key. On macOS and Linux this is
close to instant; on Windows it's the least certain of the three
platforms, since the Snipping Tool has no documented way to write
directly to a file, so images.nvim polls the clipboard for a new image
instead (`display.screenshot.windows_poll_interval_ms`, default every
600ms, up to `windows_timeout_ms` = 60s). If a Windows screenshot seems to
hang, it's still polling — give it the full minute before assuming it
failed, and fall back to `<leader>iv` after an explicit screenshot if it
does.

Both write to `assets/<document>-<timestamp>.png` by default — but check
once, in a new project, whether a `Resources` or `Ressourcen` folder
already exists next to your documents. If it does, paste/screenshot reuse
it silently instead of creating a parallel `assets/` folder. This is
usually what you want, but it means "where did my last screenshot go"
sometimes has a different answer than the default config would suggest —
`:Image info` on the freshly-inserted link settles it fast.

## Reviewing a document you didn't write

Opening someone else's (or your own six-months-old) markdown file with a
dozen image links: `:Image gallery` shows all of them at once instead of
hovering one at a time — the first move, not `:Image next` repeated a
dozen times. Once you've spotted the one that needs a closer look,
`:Image zen` on it opens a real, resizable window instead of the overlay
gallery tile, which is worth it for anything you need to actually read
(a screenshot of code, a diagram with small labels) rather than just
confirm exists.

`:Image next`/`prev` (`<leader>in`/`<leader>ip`) are for the narrower
case: you're editing near one image and want to step to its neighbors
without leaving the flow of writing, not for surveying a whole document.

## The hover you get for free, and the trap in `hover_mode`

Just moving the cursor onto a link shows the image — no command needed,
as long as the buffer's filetype is in `keymaps.filetypes` (markdown,
vimwiki, norg, text by default). The default `hover_mode = "overlay"`
draws directly over the text and clears itself the moment the cursor
moves, an insert starts, the buffer is left, or the window scrolls
(`display.clear_events`). That's the right choice for skimming a
document quickly.

**The trap:** if you switch to `hover_mode = "float"` expecting a strict
upgrade, note the scope — it only changes the single-image hover/`:Image
show` path. `:Image gallery` keeps its own grid layout regardless of
`hover_mode`, so don't expect the float behavior to show up there; it's a
container swap for one specific path, not a global display mode.

## Cleaning up a document's asset folder

Delete an image link while editing and the file is left behind on disk
— nothing in this plugin deletes a file just because a link to it
disappeared, and rightly so (an accidental undo of the deletion, with the
file already gone, would be much worse). Periodically, `:Image orphans`
finds every file in `paste.dir` that no link currently points to and
offers to delete them one at a time. Worth running before a commit that
touched a lot of images, not on every save.

## Redacting a screenshot before sharing it

`:Image redact` on a screenshot with something sensitive in it (an API
key, a face, an address in a map screenshot): opens the same full-screen
window as `:Image zen`, then `v`/`<C-v>` + move + `<CR>` marks a box,
repeat for more, `u` undoes the last mark, `w` burns every box in and
writes `<name>.redacted.png` next to the original — **the source file is
never touched**, so a mis-drawn box costs nothing but re-running the
command. The boxes are deliberately padded by `display.redact.padding_cells`
(default one cell) because a terminal has no pixel-precise mouse input at
all for this — over-redacting is the safe failure mode. Needs ImageMagick;
without it the command reports a clear error rather than silently doing
nothing.

## Comparing two versions of an image

`:Image compare cwd` (or `cfile`, or an explicit dir) after regenerating
an asset — a re-exported diagram, a resized screenshot — picks two images
from the scan and shows them side by side. With ImageMagick installed
they're scaled to their true relative size, which is the point: two
images shown at equal size would hide the fact that one export came out
2x the pixel dimensions of the other. Without ImageMagick you still get a
side-by-side view, just without that signal.

## When the picker needs to reach further than the current buffer

`:Image pickers cwd` browses every image under the working directory with
a live thumbnail per entry, if snacks.picker is installed — the tool for
"I know roughly what I'm looking for but not which file it's in", as
opposed to `:Image list`, which only ever looks at links already present
in the current buffer. `:Image pickers cfile` narrows the scope to the
directory of the file under the cursor, useful from inside a directory
listing or a buffer that references a path. `<Tab>` multi-selects in the
snacks picker specifically; confirming more than one selection shows them
as a gallery rather than opening only the first.

## Remote images: an explicit opt-in, not a silent default

Hovering a `https://…` image link does nothing until
`display.remote.enabled = true` is set — this is deliberate, the same
"load remote images" gate email clients use, so opening a document never
triggers an outbound request on its own. Once enabled, downloads are
cached by URL with `max_bytes`/`timeout_ms` limits. **The gap worth
knowing about:** only the single-image show/hover path resolves remote
images — `:Image gallery`, `compare`, `pickers` and `zen` do not, so a
document mixing local and remote images will show remote ones on hover
but skip them in a gallery view. Don't be surprised when a gallery looks
sparser than the buffer's actual link count.

## Windows/WezTerm and the ASCII fallback

If `:Image check` reports the terminal isn't recognized (SSH session,
tmux without passthrough, a genuinely unsupported terminal), `:Image
show`/hover don't just fail silently — they draw a block-character
approximation instead, sampled from the real pixel colors via
ImageMagick. This needs `display.ascii_fallback.enabled = true` (the
default) and ImageMagick present; with neither, you get the old
silent-no-op-with-a-warning. If a known-good terminal (WezTerm via
`wezterm imgcat` working from a raw shell) is still misdetected, set
`display.assume_supported = true` rather than fighting the heuristic —
there is no capability query for OSC 1337, so detection is inherently a
best guess from environment variables.

## `images.draw()` for other plugins, not just this one

If you're scripting something that needs to put an image in a specific
spot of a specific window — a custom picker preview, a dashboard widget —
reach for `images.draw(target, position, path, opts)` directly rather
than re-implementing window-vs-buffer resolution or the same-tick
repaint-ordering fix. `zen`, the hover float, redact, and the picker
preview all already delegate to it internally; a new caller opening its
own window in the same tick should pass `opts.defer = true` the same way
they do, or the image will be drawn and then immediately painted over by
Neovim's own repaint.
