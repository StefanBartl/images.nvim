---@module 'images.convert'
---@brief Format conversion via ImageMagick: SVG->PNG, image->PDF,
--- image->redacted copy.
---@description
--- Three independent conversions in one module, because all three share the
--- same `magick` dependency and the same error handling:
---
--- `M.to_png` — WezTerm decodes PNG/JPEG/GIF/WebP itself, but not SVG. Here a
--- conversion is genuinely required rather than merely an improvement —
--- deliberately the only *display* case where `magick` is a prerequisite
--- instead of a bonus (see the guardrail in docs/ROADMAP/README.md). Results
--- are cached in `stdpath("cache")/images.nvim/svg`, named after source path
--- plus modification time — a changed SVG automatically gets a new PNG rather
--- than showing a stale one.
---
--- `M.to_pdf` — the opposite direction of `pdfport.nvim`'s "PDF page as an
--- image" (see docs/ROADMAP/CROSS-PLUGIN.md): write an existing image out as a
--- PDF next to its source, e.g. to attach a screenshot to a ticket that
--- expects a PDF. No cache — unlike SVG display this is a one-off, explicit
--- export, not a repeated draw path.
---
--- If `pdfport.nvim` is installed and `can_create("image")` reports an
--- available producer, the export runs through it (asynchronously, losslessly
--- via `img2pdf`, otherwise `magick` — which producer applies is pdfport's
--- own `create_chain` to decide, not this plugin's). Without pdfport the
--- existing synchronous `magick` path remains the only option, unchanged. A
--- soft dependency via `pcall`, as everywhere in this repo (see
--- CROSS-PLUGIN.md).
---
--- `M.redact` — paint rectangles (pixel coordinates, see `images.scale`) black
--- and write the result as a new file; see docs/ROADMAP/REDACT.md for the full
--- concept (motivation: casedesk attachments containing customer data that has
--- to be made unrecognisable before any future handover to an AI). No cache,
--- like `M.to_pdf` — a one-off export, not a draw path.

local M = {}

---@param path string
---@return boolean
function M.is_svg(path)
  return (path:match("%.([%w]+)$") or ""):lower() == "svg"
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/svg"
  require("lib.nvim.fs.mkdirp")(dir)
  return dir
end

--- Convert SVG to PNG, cached by source path plus modification time.
---@param path string absolute path to a .svg file
---@return string|nil png_path
---@return string|nil err
function M.to_png(path)
  if not require("lib.nvim.cross.executable").exists("magick") then
    return nil, "SVG requires ImageMagick (`magick` not found)"
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "file not found: " .. path end

  -- sha256 of path+mtime as the file name: collision-free enough for a cache,
  -- and a changed SVG automatically gets a new key.
  local key = vim.fn.sha256(path .. ":" .. tostring(stat.mtime and stat.mtime.sec or 0))
  local out = cache_dir() .. "/" .. key .. ".png"

  if vim.uv.fs_stat(out) then return out end

  -- -background none: a transparent background rather than a guessed
  -- white/black that would look wrong on a coloured terminal background.
  local result = vim.system({ "magick", path, "-background", "none", out }, { text = true }):wait()
  if result.code ~= 0 then
    pcall(vim.uv.fs_unlink, out)
    return nil, "conversion failed: " .. vim.trim(result.stderr or "")
  end
  if not vim.uv.fs_stat(out) then return nil, "conversion produced no file" end
  return out
end

--- Export an image as a PDF next to the source file, on the same stem
--- ("image.png" -> "image.pdf"). An existing target file is overwritten — the
--- same stance as `:Image paste`/`replace`, which also write target files
--- without asking; images.nvim does not prompt on file operations as a rule,
--- it reports the outcome.
---
--- `on_done` is the only way to learn the result: both paths — pdfport and
--- magick alike — call it asynchronously once the conversion finishes. The
--- return values are therefore always nil, and set only for the cases that
--- fail before starting at all (no magick, file not found).
---@param path string absolute path to an image file
---@param on_done fun(ok: boolean, out_path_or_err: string)|nil
---@return nil  always nil -- there is no synchronous success path any more
---@return string|nil err  set only when the export fails before starting
---                        (no magick, file not found)
function M.to_pdf(path, on_done)
  local ok_pp, pdfport = pcall(require, "pdfport")
  if ok_pp and type(pdfport.can_create) == "function" and pdfport.can_create("image") then
    pdfport.create({
      inputs = { path },
      from = "image",
      __callback = function(result)
        if not on_done then return end
        if result.status == "ok" then
          on_done(true, result.path)
        else
          on_done(false, result.error or "export failed (pdfport)")
        end
      end,
    })
    return nil, nil
  end

  if not require("lib.nvim.cross.executable").exists("magick") then
    local err = "PDF export requires ImageMagick (`magick` not found)"
    if on_done then on_done(false, err) end
    return nil, err
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then
    local err = "file not found: " .. path
    if on_done then on_done(false, err) end
    return nil, err
  end

  local out = vim.fn.fnamemodify(path, ":r") .. ".pdf"

  -- `magick` used to run here through `vim.system(...):wait()`, blocking the
  -- UI thread for the whole conversion -- seconds, for a large image. Now
  -- asynchronous, exactly like the pdfport branch above: `on_done` is the route
  -- to the result in *both* paths, which is what this function's docs already
  -- describe anyway.
  vim.system({ "magick", path, out }, { text = true }, function(result)
    -- vim.system callbacks run outside the main loop; every caller's `on_done`
    -- ends up in notify and vim.fn.
    vim.schedule(function()
      if not on_done then return end
      if result.code ~= 0 then
        on_done(false, "export failed: " .. vim.trim(result.stderr or ""))
        return
      end
      if not vim.uv.fs_stat(out) then
        on_done(false, "export produced no file")
        return
      end
      on_done(true, out)
    end)
  end)

  return nil, nil
end

--- Paint rectangles black and write the result as a new file next to the
--- source ("image.png" -> "image.redacted.png"); the original stays untouched.
--- An existing target file is overwritten — the same stance as `M.to_pdf`.
---
--- `on_done` is the route to the result: `magick` used to run here through
--- `vim.system(...):wait()`, blocking the UI thread for the whole conversion.
--- With several boxes on a large screenshot that is seconds — and redaction
--- mode is exactly the situation where you want to carry straight on
--- afterwards.
---@param path string absolute path to an image file
---@param boxes { x1: integer, y1: integer, x2: integer, y2: integer }[] pixel rectangles, see `images.scale.cell_box_to_pixels`
---@param on_done fun(out_path: string|nil, err: string|nil)|nil
---@return nil
function M.redact(path, boxes, on_done)
  local function done(out_path, err)
    if on_done then on_done(out_path, err) end
  end

  if not require("lib.nvim.cross.executable").exists("magick") then
    return done(nil, "redaction requires ImageMagick (`magick` not found)")
  end
  if not boxes or #boxes == 0 then return done(nil, "no box given to redact") end

  local stat = vim.uv.fs_stat(path)
  if not stat then return done(nil, "file not found: " .. path) end

  local ext = vim.fn.fnamemodify(path, ":e")
  local out = vim.fn.fnamemodify(path, ":r") .. ".redacted." .. (ext ~= "" and ext or "png")

  local args = { "magick", path, "-fill", "black" }
  for _, box in ipairs(boxes) do
    table.insert(args, "-draw")
    table.insert(args, ("rectangle %d,%d %d,%d"):format(box.x1, box.y1, box.x2, box.y2))
  end
  table.insert(args, out)

  vim.system(args, { text = true }, function(result)
    -- vim.system callbacks run outside the main loop; the caller notifies and
    -- closes a window.
    vim.schedule(function()
      if result.code ~= 0 then
        done(nil, "redaction failed: " .. vim.trim(result.stderr or ""))
        return
      end
      if not vim.uv.fs_stat(out) then
        done(nil, "redaction produced no file")
        return
      end
      done(out, nil)
    end)
  end)
end

return M
