---@module 'images.redact'
---@brief Redaction mode: black out parts of an image in a zen-like window,
--- leaving the original intact.
---@description
--- Concept: docs/ROADMAP/REDACT.md. Motivation: casedesk attachments
--- (screenshots containing customer data under `Ressources/`) that have to be
--- made unrecognisable before any future handover to an AI.
---
--- The real obstacle is that an image drawn via OSC 1337 is not interactive as
--- far as Neovim is concerned — mouse and cursor yield cell coordinates only,
--- never pixel coordinates within the image. The solution here: the selection
--- happens entirely in cells, through genuine Neovim visual mode on a
--- space-filled scratch buffer sized to the image (`v`/`<C-v>` + `<CR>` marks a
--- box, the same idea as visual block) — no new input system, no pixel
--- arithmetic during selection. The conversion happens once, on write (`w`):
--- `images.scale.fit_cells` picks the draw box so `preserveAspectRatio=1` has
--- almost nothing left to letterbox (the cell count is fitted to the image's
--- aspect ratio via an assumed, documented cell width/height,
--- `images.scale.CELL_ASPECT` — not a real cell measurement, see there), and
--- `images.scale.cell_box_to_pixels` converts to pixel coordinates with a
--- safety margin. The burn-in goes through `images.convert.redact`
--- (ImageMagick, the third deliberate exception to the "ImageMagick is never
--- required" guardrail, alongside SVG display and `:Image export`).
---
--- **Not part of the automated test suite**: the key logic itself (visual mode
--- capture, window construction) needs a real terminal with OSC 1337 support to
--- be verified meaningfully — as everywhere in this suite, "drawing" stays
--- unchecked (see TESTS/zen_spec.lua). The pure geometry
--- (`images.scale.fit_cells`/`cell_box_to_pixels`) and the burn-in
--- (`images.convert.redact`) are tested.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@type integer|nil
local winid = nil
---@type integer|nil
local bufnr = nil
---@type string|nil
local file = nil
---@type Images.Scale.Dims|nil
local image_px = nil
---@type integer
local draw_cols = 0
---@type integer
local draw_rows = 0

---@class Images.Redact.Box
---@field row1 integer
---@field col1 integer
---@field row2 integer
---@field col2 integer

---@type Images.Redact.Box[]
local boxes = {}

local ns = vim.api.nvim_create_namespace("images.redact")

--- Whether a redaction window is currently open.
---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Close the redaction window (a no-op when none is open). Discards
--- unconfirmed boxes — original and target file are untouched at that point
--- anyway, only `w` actually writes.
---@return nil
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  if winid then require("images.terminal").clear() end
  winid, bufnr, file, image_px, draw_cols, draw_rows = nil, nil, nil, nil, 0, 0
  boxes = {}
end

---@return nil
local function redraw_boxes()
  if not bufnr then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, box in ipairs(boxes) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, box.row1 - 1, box.col1 - 1, {
      end_row = box.row2 - 1,
      end_col = box.col2,
      hl_group = "Visual",
    })
  end
end

---@return nil
local function undo_box()
  if #boxes == 0 then
    notify().warn("no box to remove")
    return
  end
  table.remove(boxes)
  redraw_boxes()
  notify().info(("box removed (%d remaining)"):format(#boxes))
end

--- Take the current visual selection as a redaction box. Runs as a visual mode
--- mapping — `getpos("v")`/`getpos(".")` are still valid while the callback
--- executes; an `<Esc>` afterwards leaves the mode.
---@return nil
local function confirm_box()
  local vstart = vim.fn.getpos("v")
  local vend = vim.fn.getpos(".")
  vim.cmd("normal! \27")

  local row1, col1 = vstart[2], vstart[3]
  local row2, col2 = vend[2], vend[3]
  if row1 > row2 then
    row1, row2 = row2, row1
  end
  if col1 > col2 then
    col1, col2 = col2, col1
  end

  boxes[#boxes + 1] = { row1 = row1, col1 = col1, row2 = row2, col2 = col2 }
  redraw_boxes()
  notify().info(("box %d marked"):format(#boxes))
end

---@return nil
local function write_redacted()
  if #boxes == 0 then
    notify().warn("no box marked — nothing to redact")
    return
  end
  if not file or not image_px then return end

  local padding = cfg().display.redact.padding_cells or 0
  local pixel_boxes = {}
  for _, box in ipairs(boxes) do
    pixel_boxes[#pixel_boxes + 1] = require("images.scale").cell_box_to_pixels(box, draw_cols, draw_rows, image_px, padding)
  end

  -- convert.redact() is asynchronous: magick used to block here for the whole
  -- conversion. The window stays up until the result arrives and is closed only
  -- in the callback — so the ordering is the same as before, just without a
  -- frozen editor.
  require("images.convert").redact(file, pixel_boxes, function(out, err)
    if not out then
      notify().error(err or "redaction failed")
      return
    end

    notify().info("redacted copy saved: " .. vim.fn.fnamemodify(out, ":~"))
    M.close()
  end)
end

--- Open an image — or the one under the cursor — in redaction mode.
---@param path string|nil nil = the image under the cursor
---@return boolean ok
function M.open(path)
  local target = require("images.resolve").path_or_cursor(path)
  if not target then
    notify().warn("no image under the cursor or at the given path")
    return false
  end

  local px, info_err = require("images.info").collect(target)
  if not px or not px.width or not px.height then
    notify().error(info_err or "cannot determine the image dimensions — `:Image redact` needs ImageMagick")
    return false
  end

  require("images.guard").check()
  M.close()

  local max_cols, max_rows = require("images.zen").dimensions(cfg().display.zen)
  local cols, rows = require("images.scale").fit_cells(max_cols, max_rows, px)

  local lines = {}
  local blank = (" "):rep(cols)
  for i = 1, rows do
    lines[i] = blank
  end

  local win, buf = require("lib.nvim.window.make_scratch")({
    lines = lines,
    width = cols,
    height = rows,
    modifiable = false,
    nice_quit = true,
    title = " Redact: " .. vim.fn.fnamemodify(target, ":t") .. " ",
  })
  if not win or not buf then
    notify().error("could not open the redaction window")
    return false
  end

  winid, bufnr, file, image_px, draw_cols, draw_rows = win, buf, target, px, cols, rows
  boxes = {}

  local map = require("lib.nvim.map")
  map("n", "w", write_redacted, { buffer = buf, nowait = true }, "images.redact: redact and save")
  map("n", "u", undo_box, { buffer = buf, nowait = true }, "images.redact: remove the last box")
  map("x", "<CR>", confirm_box, { buffer = buf, nowait = true }, "images.redact: mark the selection as a box")

  local autocmd = require("lib.nvim.autocmd")
  autocmd.create("WinClosed", function()
    winid = nil
    require("images.terminal").clear()
  end, {
    group = autocmd.group("images.redact", true),
    pattern = tostring(win),
    once = true,
    desc = "images.redact: clean up on close",
  })

  -- `defer = true` for the same reason as in `images.zen` — see
  -- `images.anchor`'s module docs: the window has only just been opened.
  -- `inset = 0`: here the draw box is not a presentation choice but the basis
  -- for mapping back. `draw_cols`/`draw_rows` above and
  -- `images.scale.cell_box_to_pixels` assume the box drawn is exactly the one
  -- `fit_cells` determined. A safety margin would map every marked box onto the
  -- wrong part of the image — what got blacked out would not be what the user
  -- marked.
  require("images.anchor").draw(win, "full", target, {
    defer = true,
    inset = 0,
    on_done = function(ok, err)
      if not ok then notify().error(err or "could not display the image") end
    end,
  })

  return true
end

return M
