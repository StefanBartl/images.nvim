---@module 'images.cell'
---@brief Pixel aspect ratio of a terminal cell.
---@description
--- `images.scale.CELL_ASPECT` assumes a cell is twice as tall as it is wide
--- (0.5). That is roughly right for common monospace fonts and good enough for
--- `images.redact`, but it is an assumption: if the real cell is 0.46,
--- `images.scale.fit_cells` computes a box one or two rows taller than the
--- image inside it can ever fill. The terminal scales to "contain" under
--- `preserveAspectRatio=1` and the remainder stays visibly empty — in a hover
--- float whose frame *is* that box, the empty strip below the image is
--- immediately obvious.
---
--- **Why this is configured rather than measured.** The obvious query is
--- `CSI 16 t`; the terminal answers with `CSI 6 ; <height> ; <width> t`. That
--- answer is unreachable from a Neovim plugin: per `:h TermResponse`, the
--- event fires only for **DA1, OSC, DCS and APC** responses, and
--- `CSI 6 ; … t` is a plain CSI response. It is never forwarded, whatever the
--- terminal. `nvim_list_uis()` knows only cell dimensions (`width`/`height` in
--- cells), no pixels. So there is no route from Neovim to the real cell size —
--- an earlier attempt via `CSI 16 t` + `TermResponse` lived here and never
--- worked, for exactly that reason. Details and measurements:
--- `docs/ROADMAP/TERMINALS.md`.
---
--- Hence: set `display.cell_aspect` if you want it exact; otherwise the
--- assumption stands. That is no worse than before — the assumption was always
--- the value actually in effect.
---
--- The value is written into `images.scale.CELL_ASPECT` rather than passed to
--- every caller: `fit_cells` has four of them (`ascii`, `redact`, `zen` and
--- markdown.nvim's hover canvas), and an extra signature slot all four would
--- have to carry would hold the same value in every single case. It also keeps
--- `images.scale` the pure, terminal-free computation module its own docs say
--- it should be.

local M = {}

--- `images.scale.CELL_ASPECT` in its original state, captured once: `M.apply`
--- overwrites the field, and without this copy the fallback after the first
--- `apply` would be its own previous output rather than the documented
--- assumption.
---@type number|nil
local assumed = nil

---@return number
local function assumption()
  if not assumed then assumed = require("images.scale").CELL_ASPECT end
  return assumed
end

--- The effective ratio: configuration beats assumption.
---@return number
function M.aspect()
  local ok, config = pcall(require, "images.config")
  if ok then
    local configured = (config.get().display or {}).cell_aspect
    if type(configured) == "number" and configured > 0 then return configured end
  end
  return assumption()
end

--- Write the effective ratio into `images.scale.CELL_ASPECT`, where all four
--- callers of `fit_cells` already read it.
---@return number applied
function M.apply()
  local aspect = M.aspect()
  require("images.scale").CELL_ASPECT = aspect
  return aspect
end

return M
