---@module 'images.terminal'
---@brief Draw images in the terminal via the iTerm2 protocol (OSC 1337).
---@description
--- Why OSC 1337 and not the Kitty graphics protocol:
---
--- On native Windows Neovim in WezTerm, the terminal draws only OSC 1337 when
--- it comes from Neovim. Kitty APC (`ESC _G`) never arrives — in a raw pwsh
--- both protocols work, so the difference is introduced by Neovim's output
--- layer. Since `snacks.image` and `image.nvim` both send Kitty APC only, they
--- are fundamentally unusable there, whatever the configuration.
---
--- Five peculiarities that cost time while building this:
---
--- * Output goes through `vim.api.nvim_ui_send`, not `io.stdout:write`. The
---   latter only draws the first time per terminal session.
--- * Without cursor positioning the image lands at the bottom edge and pushes
---   the status line up. Hence `ESC[s` / `ESC[<row>;<col>H` / payload /
---   `ESC[u`.
--- * Those parts must go out in **one** `nvim_ui_send`, see `sequence_for`.
---   Neovim's own TUI renderer writes to the same tty stream; between two
---   calls it may flush and insert cursor movements of its own. If that
---   happens between positioning and payload, the terminal draws the image
---   wherever Neovim's cursor currently sits — the same result as no
---   positioning at all, only sporadic rather than consistent, and therefore
---   far harder to attribute.
--- * An image reaching past the last row scrolls the whole screen — Neovim's
---   grid included. `ESC[u` restores the cursor position afterwards but not the
---   scroll: the status line stays pushed up until `M.clear` repaints
---   everything via `:mode`. `clamp_to_screen` prevents it.
--- * `width`/`height` are given in **cells**, not pixels. Together with
---   `preserveAspectRatio=1` the terminal scales on its own, and the pixel size
---   of a cell never has to be known anywhere.
---
--- The protocol has no image IDs: what has been drawn cannot be removed
--- individually, only the whole screen can be repainted. Hence this module
--- keeps a single flag rather than a placement registry.

local M = {}

local ESC, BEL = "\27", "\7"

--- Whether at least one image is currently on screen.
---@type boolean
local showing = false

---@return boolean
function M.is_showing()
  return showing
end

--- Whether terminal output is available at all.
--- `nvim_ui_send` exists from API level 14 onwards.
---@return boolean
function M.available()
  return type(vim.api.nvim_ui_send) == "function"
end

---@class Images.Capability
---@field ok boolean whether drawing is possible
---@field terminal string|nil detected terminal name
---@field reason string|nil why, when `ok` is false
---@field hint string|nil concrete next step for the user

--- Result of the capability check, determined once per session.
---@type Images.Capability|nil
local capability = nil

--- Terminals implementing the iTerm2 protocol, with the environment variable
--- they can be recognised by. Deliberately short: OSC 1337 has no capability
--- query, so a list of names is all there is.
---@type { name: string, detect: fun(): boolean }[]
local KNOWN = {
  {
    name = "WezTerm",
    detect = function()
      return (vim.env.WEZTERM_EXECUTABLE or vim.env.WEZTERM_VERSION or vim.env.WEZTERM_PANE) ~= nil
    end,
  },
  {
    name = "iTerm2",
    detect = function()
      local tp = (vim.env.TERM_PROGRAM or ""):lower()
      return tp:find("iterm", 1, true) ~= nil or (vim.env.LC_TERMINAL or ""):lower():find("iterm", 1, true) ~= nil
    end,
  },
  {
    name = "Konsole",
    detect = function()
      return vim.env.KONSOLE_VERSION ~= nil
    end,
  },
}

--- Check whether this terminal can display images.
---
--- Deliberately *not* a hard block: detection is a heuristic over environment
--- variables, because OSC 1337 has no query. A false negative would otherwise
--- break a working setup. The caller decides what to do with `ok = false` —
--- this only reports.
---
--- The result is memoized: the environment does not change within a session,
--- and this call sits in front of every draw.
---@param force boolean|nil skip detection and assume support
---@return Images.Capability
function M.capability(force)
  if capability then return capability end

  if not M.available() then
    capability = {
      ok = false,
      reason = "`nvim_ui_send` is missing (requires API level 14)",
      hint = "update Neovim -- without this API no image can be drawn",
    }
    return capability
  end

  local detected
  for _, term in ipairs(KNOWN) do
    local ok_detect, hit = pcall(term.detect)
    if ok_detect and hit then
      detected = term.name
      break
    end
  end

  if detected then
    capability = { ok = true, terminal = detected }
  elseif force then
    capability = { ok = true, terminal = nil }
  else
    capability = {
      ok = false,
      reason = "terminal not recognised (TERM_PROGRAM=" .. (vim.env.TERM_PROGRAM or "empty") .. ")",
      hint = "test with `wezterm imgcat image.png` or the equivalent. "
        .. "If that works, set `display.assume_supported = true`.",
    }
  end

  -- tmux only forwards the sequences with allow-passthrough. That holds for a
  -- recognised terminal too, hence here rather than in the else branch.
  if vim.env.TMUX and vim.env.TMUX ~= "" and capability.ok then
    capability.hint = "under tmux: `set -g allow-passthrough on` is required, or nothing arrives"
  end

  return capability
end

--- Discard the memoized check result. For tests, and for the case where the
--- configuration changed after the first check.
---@return nil
function M.reset_capability()
  capability = nil
end

--- Read a file's contents. SVG is converted to PNG first (see
--- `images.convert`) — OSC 1337 expects raster bytes and WezTerm cannot decode
--- SVG itself. For every other format this is a plain pass-through.
---@param file string
---@return string|nil data
---@return string|nil err
local function read_file(file)
  if type(file) ~= "string" or file == "" then return nil, "no file path given" end

  local effective = file
  if require("images.convert").is_svg(file) then
    local png, conv_err = require("images.convert").to_png(file)
    if not png then return nil, conv_err end
    effective = png
  end

  local raw, read_err = require("lib.nvim.fs.read")(effective)
  if not raw then return nil, ("file not readable: %s (%s)"):format(effective, read_err or "?") end
  if raw == "" then return nil, "file is empty: " .. effective end
  return raw
end

--- Build the OSC 1337 sequence for an image file's contents.
---@param raw string raw file bytes
---@param cols integer width in cells
---@param rows integer height in cells
---@return string
local function payload_for(raw, cols, rows)
  -- table.concat rather than repeated `..` concatenation: for large images the
  -- base64 part runs to several hundred KB, so every intermediate copy counts.
  return table.concat({
    ESC,
    "]1337;File=inline=1",
    ";size=" .. #raw,
    ";width=" .. cols,
    ";height=" .. rows,
    ";preserveAspectRatio=1",
    ":",
    vim.base64.encode(raw),
    BEL,
  })
end

--- Clip the draw box so it fits on screen.
---
--- One row is left free vertically, and that is not a safety margin out of
--- caution: OSC 1337 with `inline=1` advances the cursor down by the image's
--- height. If the image ends on the last row, that single step triggers the
--- very scroll the box itself only just avoided — and a scroll shifts Neovim's
--- entire grid without Neovim finding out (see the module docs).
---@param row integer 1-based terminal row
---@param col integer 1-based terminal column
---@param cols integer requested width in cells
---@param rows integer requested height in cells
---@return integer cols
---@return integer rows
local function clamp_to_screen(row, col, cols, rows)
  return math.max(1, math.min(cols, vim.o.columns - col + 1)), math.max(1, math.min(rows, vim.o.lines - row))
end

--- The complete sequence for one image at one position — as **one** string
--- that goes out in a single piece. Why it has to stay together is in the
--- module docs; the only addition here is `ESC[?7l`/`ESC[?7h`: autowrap off,
--- so that a pixel of excess width cannot force a line break, which would in
--- turn scroll at the bottom edge.
---@param raw string raw file bytes
---@param row integer 1-based terminal row
---@param col integer 1-based terminal column
---@param cols integer width in cells
---@param rows integer height in cells
---@return string
local function sequence_for(raw, row, col, cols, rows)
  return table.concat({
    ESC .. "[s", -- save cursor
    ESC .. "[?7l", -- autowrap off
    ("%s[%d;%dH"):format(ESC, row, col), -- position
    payload_for(raw, cols, rows),
    ESC .. "[?7h", -- autowrap back on
    ESC .. "[u", -- restore cursor
  })
end

--- Force pending screen output BEFORE drawing.
---
--- A sixth peculiarity that cost time: `nvim_ui_send` writes to the terminal
--- immediately, whereas Neovim's own repaint only runs once control returns to
--- the main loop. Open a window and draw into it in the same tick and the
--- image goes out, after which Neovim paints that window's (empty) cells over
--- it — popup there, image gone. That is exactly how `:Image zen` behaved.
---
--- Hence here and not at the caller: it is an invariant of the draw path, not
--- of window logic. Where the screen is settled anyway (`images.browse`'s
--- picker preview, `images.gallery` over existing text) it is an ineffective
--- flush.
---@return nil
local function flush_pending_redraw()
  pcall(vim.cmd, "redraw")
end

--- Draw an image at a terminal position.
---
--- `cols`/`rows` are a request, not a promise: whatever no longer fits on
--- screen from `row`/`col` onwards is clipped away first (`clamp_to_screen`).
--- An oversized value therefore costs image size, not the screen's integrity.
---@param file string absolute path to an image file
---@param row integer 1-based terminal row
---@param col integer 1-based terminal column
---@param cols integer requested width in cells, clipped to the screen
---@param rows integer requested height in cells, clipped to the screen
---@return boolean ok
---@return string|nil err
function M.draw(file, row, col, cols, rows)
  if not M.available() then return false, "terminal output unavailable (nvim_ui_send missing, requires API level 14)" end

  -- Before reading: if the read fails the flush was pointless but harmless --
  -- the other way round it would come too late.
  local raw, err = read_file(file)
  if not raw then return false, err end

  -- `display.terminal_padding` may be negative (see `images.anchor`), and near
  -- the top/left edge that can arithmetically fall below 1. `CSI 0;0H` does
  -- behave like `CSI 1;1H` in practice, but nothing here should rely on it --
  -- and `clamp_to_screen` would derive an oversized height from too small a
  -- `row`.
  row = math.max(1, row)
  col = math.max(1, col)

  cols, rows = clamp_to_screen(row, col, cols, rows)

  flush_pending_redraw()

  vim.api.nvim_ui_send(sequence_for(raw, row, col, cols, rows))

  showing = true
  return true
end

---@class Images.Placement
---@field file string absolute path
---@field row integer 1-based terminal row
---@field col integer 1-based terminal column
---@field cols integer width in cells
---@field rows integer height in cells

--- Draw several images in one go.
---
--- Every tile goes out as its own self-contained sequence (save cursor,
--- position, draw, restore) rather than one save for the whole block. That
--- costs a few extra bytes per tile but is the entire point: only this way
--- does each positioning stick inseparably to its payload. Concatenating
--- everything into a single string would be stricter still, but would then
--- hold every base64 payload of a gallery in memory at once.
---@param placements Images.Placement[]
---@return integer drawn number of images actually drawn
---@return string[] errors messages for the skipped images
function M.draw_many(placements)
  if not M.available() then return 0, { "terminal output unavailable (nvim_ui_send missing)" } end

  local send = vim.api.nvim_ui_send
  local drawn, errors = 0, {}

  flush_pending_redraw()

  for _, p in ipairs(placements) do
    local raw, err = read_file(p.file)
    if raw then
      local cols, rows = clamp_to_screen(p.row, p.col, p.cols, p.rows)
      send(sequence_for(raw, p.row, p.col, cols, rows))
      drawn = drawn + 1
    else
      errors[#errors + 1] = err or ("skipped: " .. tostring(p.file))
    end
  end

  if drawn > 0 then showing = true end
  return drawn, errors
end

--- Remove every displayed image. `:mode` forces a full repaint that overwrites
--- the occupied cells without clearing the screen.
---@return nil
function M.clear()
  if not showing then return end
  showing = false
  pcall(vim.cmd, "mode")
end

return M
