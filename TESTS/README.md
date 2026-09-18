# TESTS/

The headless test suite for images.nvim. No plenary, no busted — a small
framework-free harness (`harness.lua`) and an aggregator (`run.lua`) that
loads every `*_spec.lua` and runs it against that harness. See
[docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md) for the workflow this fits
into; this file is about what is actually covered.

## Running it

```sh
nvim --headless -u NONE -l TESTS/run.lua
```

Needs [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) on the
runtimepath — a real dependency, not a test-only one (`run.lua` resolves a
sibling checkout, `$LIB_NVIM_PATH`, or `stdpath("data")/lazy/lib.nvim`, in
that order, and refuses to run at all without it). `gopath.nvim` and
`ui.nvim` are soft dependencies resolved the same way, each spec skipping the
block that needs it when it cannot be found — see `run.lua`'s and
`menu_spec.lua`'s own comments for the one place that convention gets
inverted on purpose.

CI (`.github/workflows/ci.yml`) runs this, `stylua --check` and `luacheck`
on every push and PR to `main`, plus a separate job that generates the
module map.

## What "covered" means here

A file with real branching logic gets a spec that asserts real behaviour —
not a `require()` smoke test. Three categories are deliberately excluded, and
staying honest about which is which matters more than the count of spec
files:

1. **UI that needs a real live backend.** Anything that opens a floating
   window and actually draws into it needs a terminal speaking a graphics
   protocol (OSC 1337) or block-graphics rendering that a headless run cannot
   observe. Where a module's *state machine* (`is_open`/`close`) is separable
   from its *draw call*, the state machine gets a spec and the draw call
   stays untested, with a comment saying so — see `redact_spec.lua`,
   `ascii_spec.lua`, `zen_spec.lua`. Fully interactive flows with no
   pure remainder (`images.calibrate`'s nudge loop, `images.debug`'s
   measurement tools) have no spec at all; they are diagnostic/calibration
   tools, not commands with a testable contract.
2. **Pure `@types`/`---@meta` files.** `lua/images/@types/init.lua` has no
   runtime behaviour to assert against.
3. **Real external processes.** Subprocess/network calls that cannot be
   stubbed without losing the point of the test (e.g. an actual `magick`
   invocation's pixel output) are exercised only up to the seam — `vim.system`
   and `require()`d command wrappers are stubbed at `package.loaded` *before*
   the module under test is required, per the module's own convention (see
   `paste_target_spec.lua`, `screenshot_spec.lua`).

Everything else with real branching logic has an assertion-based spec.

## Coverage by module

| Module | Spec | Notes |
| --- | --- | --- |
| `anchor.lua` | `anchor_spec.lua` | Positioning arithmetic across every `position` value |
| `ascii.lua` | `ascii_spec.lua` | `is_open`/`close`/`available()` only — drawing needs ImageMagick + a real window |
| `blocks.lua` | `blocks_spec.lua` | Geometry, sampling, painting, highlight-group budget |
| `browse.lua` | `browse_spec.lua` | `walk`/`roots`/scope resolution — `open()`'s picker UI stays untested |
| `calibrate.lua` | — | Fully interactive (nudge loop + floating window); no pure remainder to test |
| `calibration.lua` | `calibration_spec.lua` | Persistence, merge-not-discard, zero-is-a-value, config precedence, corrupt-file survival |
| `cell.lua` | `cell_spec.lua` | Effective aspect ratio: assumption vs. configured vs. invalid, and where `apply()` writes it |
| `compare.lua` | `compare_spec.lua` | The ui.nvim-availability guard only — `ui.kit.compare`'s UI stays untested. See "Bug fixed during this audit" below |
| `config/` | `config_spec.lua` | Defaults, merge, validation |
| `convert.lua` | `convert_spec.lua` | Format/resize/optimise argument building and callback wiring |
| `debug.lua` | — | Diagnostic/measurement tool; every function draws into a real window on purpose |
| `gallery.lua` | `gallery_spec.lua` | Grid layout arithmetic |
| `guard.lua` | `guard_spec.lua` | The shared capability guard's warn-once/reset state machine |
| `health.lua` | — (checked manually) | Every "dependency missing" branch returns before calling further into that dependency — see below |
| `hover_float.lua` | `hover_float_spec.lua` | State/lifecycle only |
| `info.lua` | `info_spec.lua` | Metadata formatting |
| `init.lua` | (exercised via `keymaps_spec.lua`/`usrcmds_spec.lua`/`blocks_spec.lua`) | The command surface itself is thin wiring over already-tested modules |
| `integrations/menu.lua` | `menu_spec.lua` | `enable`/filetype gating, `submenu()`'s empty case — real `ui.contextmenu`, resolved locally (see the spec's header) |
| `integrations/picker.lua` | `picker_integration_spec.lua` | Item shaping |
| `ocr.lua` | `ocr_spec.lua` | Binary discovery, language parsing |
| `orphans.lua` | `orphans_spec.lua` | Orphan detection |
| `paste.lua` | `paste_target_spec.lua` | Filename sanitising and target-path resolution |
| `pdf.lua` | `pdf_spec.lua` | Page/DPI config reading |
| `pixels.lua` | `pixels_spec.lua` | Raw pixel sampling arithmetic |
| `redact.lua` | `redact_spec.lua` | `is_open`/`close` only — box-marking is interactive |
| `remote.lua` | `remote_spec.lua` | URL detection |
| `resolve.lua` | `resolve_spec.lua` | Link scanning, extension checks, path resolution, the `vim.fn.expand` shell-injection regression |
| `scale.lua` | `scale_spec.lua` | Fit/compute arithmetic |
| `scan.lua` | `scan_spec.lua` | Buffer scanning, line-range restriction, found/missing split |
| `screenshot.lua` | `screenshot_spec.lua` | Availability detection |
| `terminal.lua` | `terminal_draw_spec.lua`, `capability_spec.lua` | Draw-call shaping and terminal-capability detection |
| `testcard.lua` | `testcard_spec.lua` | Generated PNG correctness |
| `zen.lua` | `zen_spec.lua` | State/lifecycle only |
| `bindings/autocmds.lua` | — | One autocmd registration, no branching |
| `bindings/keymaps.lua` | `keymaps_spec.lua` | Filetype gating, buffer-local registration |
| `bindings/usrcmds.lua` | `usrcmds_spec.lua` | Subcommand routing and completion |

## The four checks this pass looked for specifically

(Found across a wider cross-repo campaign; each checked here on its own
merits, not assumed absent.)

- **A "dependency missing" branch that still calls into that dependency.**
  Read through by hand: `health.lua`'s eleven checks each `return` (or fall
  through a branch that does not touch the missing thing) as soon as a
  prerequisite is absent — `check_pdf`, `check_ocr` and `check_clipboard` in
  particular each have three-way branches (off / dependency missing / tool
  missing) that return at every non-final step. Not found here.
- **A non-idempotent augroup.** Every `autocmd.group(name, ...)` call in this
  codebase passes `clear = true` (`ascii.lua`, `bindings/autocmds.lua`,
  `hover_float.lua`, `redact.lua`, `integrations/picker.lua`, `zen.lua`,
  `init.lua`'s `arm_clear`) — checked against `lib.nvim`'s own
  `autocmd.group()`, which re-clears on a cache hit too when asked. Not
  found here.
- **Byte/display-column/char-index confusion.** `resolve.under_cursor`
  compares `nvim_win_get_cursor`'s column against `line:find`-derived ranges
  — both are byte offsets in Lua string operations, consistently. Not found
  here.
- **Windows path bugs.** `resolve.to_path` normalises `\` to `/` explicitly
  (with the reasoning for why in its own comment) and `M.to_path`'s remote-URL
  check requires literal `://`, which a `C:\` drive path never produces.
  Verified empirically on this machine (Windows 11), not just by inspection.

## Bug fixed during this audit

`images.compare`'s `M.open` called `require("ui.kit").compare(...)` directly,
with no `pcall`. docs/installation.md documents ui.nvim as optional
everywhere else ("falls back to `vim.ui.select`"), and every other
ui.kit-backed path in this plugin (`images.init`'s `kit()`, `images.browse`'s
`open_select`) resolves it with `pcall` and degrades cleanly. `:Image
compare` was the one path that did not: without ui.nvim installed, running it
with two or more images raised an uncaught `module 'ui.kit' not found`
error instead. Fixed to `pcall` the require and report a clear message
instead (there is no `vim.ui.select` equivalent for a two-image
SEARCH->MARKED->COMPARE flow, so unlike `:Image list` this command still
needs ui.nvim — it just says so now instead of crashing).
`compare_spec.lua` pins the fix: confirmed failing against the pre-fix code
before being added, per usual regression-test practice.
