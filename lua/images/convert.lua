---@module 'images.convert'
---@brief Everything that reads an image file and writes another one, through
--- ImageMagick: SVG->PNG, image->PDF, redacted copy, crop, resize, optimise,
--- format change.
---@description
--- One module, because every one of these shares the same `magick`
--- dependency, the same argv-plus-async-`vim.system` shape and the same error
--- handling. Splitting them by theme would have produced two modules with one
--- identical error path each.
---
--- Note the name collision that is NOT one: `images.scale` is a different
--- module entirely — pure display arithmetic (cells, aspect ratio, anchors)
--- that never touches a file. `M.resize` below is the one that writes.
--- The user-facing command for it is `:Image scale`, because that is the word
--- people reach for; the internal name stays `resize` so prose about
--- `images.scale` keeps meaning exactly one thing.
---
--- The first three conversions:
---
--- `M.to_png` — WezTerm decodes PNG/JPEG/GIF/WebP itself, but not SVG. Here a
--- conversion is genuinely required rather than merely an improvement —
--- deliberately the only *display* case where `magick` is a prerequisite
--- instead of a bonus (a deliberate guardrail). Results
--- are cached in `stdpath("cache")/images.nvim/svg`, named after source path
--- plus modification time — a changed SVG automatically gets a new PNG rather
--- than showing a stale one.
---
--- `M.to_pdf` — the opposite direction of `pdfport.nvim`'s "PDF page as an
--- image": write an existing image out as a
--- PDF next to its source, e.g. to attach a screenshot to a ticket that
--- expects a PDF. No cache — unlike SVG display this is a one-off, explicit
--- export, not a repeated draw path.
---
--- If `pdfport.nvim` is installed and `can_create("image")` reports an
--- available producer, the export runs through it (asynchronously, losslessly
--- via `img2pdf`, otherwise `magick` — which producer applies is pdfport's
--- own `create_chain` to decide, not this plugin's). Without pdfport the
--- existing synchronous `magick` path remains the only option, unchanged. A
--- soft dependency via `pcall`, as everywhere in this repo.
---
--- `M.redact` — paint rectangles (pixel coordinates, see `images.scale`) black
--- and write the result as a new file (motivation: casedesk attachments containing customer data that has
--- to be made unrecognisable before any future handover to an AI). No cache,
--- like `M.to_pdf` — a one-off export, not a draw path.
---
--- And the three added for the "image operations are file operations" theme:
---
--- `M.resize`, `M.optimise`, `M.to_format` — all three write a NEW file next
--- to the source and never touch the original, the same stance `M.redact`
--- takes and for the same reason: the source is a customer's attachment, and
--- an operation that edits it in place is one undo away from losing evidence.
--- Only `M.to_format` can collide with an existing file (`photo.jpg` ->
--- `photo.png` when a `photo.png` is already there); it refuses only the case
--- where target and source are the same file, and otherwise overwrites, like
--- every other write in this plugin.

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

-- ── Image operations as file operations ─────────────────────────────────────

--- Shared preflight for `M.resize`/`M.optimise`/`M.to_format`: ImageMagick
--- present, source readable. Three copies of these six lines was the
--- alternative.
---@param path string
---@return boolean ok
---@return string|nil err
local function precheck(path)
  if not require("lib.nvim.cross.executable").exists("magick") then
    return false, "this needs ImageMagick (`magick` not found)"
  end
  if not vim.uv.fs_stat(path) then return false, "file not found: " .. path end
  return true, nil
end

--- Run `magick` and report the resulting file, or why there is none.
---@param args string[] full argv, `magick` included
---@param out string expected output path
---@param label string verb for the error message ("resize", "optimise", …)
---@param on_done fun(out_path: string|nil, err: string|nil)|nil
---@return nil
local function run_magick(args, out, label, on_done)
  vim.system(args, { text = true }, function(result)
    -- vim.system callbacks run outside the main loop; callers notify.
    vim.schedule(function()
      if not on_done then return end
      if result.code ~= 0 then
        pcall(vim.uv.fs_unlink, out)
        return on_done(nil, label .. " failed: " .. vim.trim(result.stderr or ""))
      end
      if not vim.uv.fs_stat(out) then return on_done(nil, label .. " produced no file") end
      on_done(out, nil)
    end)
  end)
end

--- Whether `spec` is a geometry ImageMagick's `-resize` understands.
---
--- Validated here rather than left to `magick`, because `magick` accepts a
--- surprising amount of nonsense silently: an unparseable geometry is treated
--- as "no geometry at all" and the image comes back at its original size, with
--- exit code 0. A typo would then produce a `.scaled.` copy that is not
--- scaled, which is worse than an error.
---@param spec string|nil whatever the user typed; anything that is not a geometry is `false`
---@return boolean
function M.valid_geometry(spec)
  if type(spec) ~= "string" or spec == "" then return false end
  return spec:match("^%d+%%$") ~= nil -- 50%
    or spec:match("^%d+x%d+!?$") ~= nil -- 800x600, 800x600! (force, ignores aspect)
    or spec:match("^%d+x$") ~= nil -- 800x   (width, height follows)
    or spec:match("^x%d+$") ~= nil -- x600   (height, width follows)
    or spec:match("^%d+$") ~= nil -- 800    (fits inside 800x800, magick's own reading)
end

--- Whether `spec` is a crop geometry ImageMagick will act on.
---
--- Separate from `M.valid_geometry`, which answers for `-resize`: the two
--- accept different shapes, and a resize geometry handed to `-crop` is not a
--- smaller mistake than an unparseable one. Only the explicit
--- `WIDTHxHEIGHT+X+Y` form is accepted -- magick also reads `WxH` alone (a
--- tiling operation that yields *many* images) and bare offsets, and neither
--- is what a caller asking for "this rectangle" means.
---@param spec string|nil
---@return boolean
function M.valid_crop(spec)
  if type(spec) ~= "string" or spec == "" then return false end
  return spec:match("^%d+x%d+[+-]%d+[+-]%d+$") ~= nil
end

--- Write the rectangle `spec` of `path` to `out`.
---
--- **The caller names the destination, and that is the difference from
--- `M.resize`/`M.optimise`/`M.to_format`.** Those three are user-facing
--- exports and write next to the source on purpose. A crop is asked for by a
--- *draw path* -- something that wants a detail on screen now and will throw
--- it away later -- so the file belongs wherever that caller sweeps, the same
--- stance `M.to_png` takes with its SVG cache. Writing `photo.cropped.png`
--- next to a customer's attachment on every keypress would be litter.
---
--- `+repage` is not optional: without it the crop keeps the source's canvas
--- offset, and everything downstream (a draw, a further resize) places the
--- result against a virtual canvas the size of the original rather than
--- against its own pixels.
---
--- `opts.fit` is an optional `-resize` geometry applied *after* the crop, in
--- the same process. That is the whole reason it exists here rather than as a
--- second call: two `magick` invocations cost two process starts, measured at
--- ~71 ms each on Windows, for an operation whose total is ~250 ms.
---@param path string absolute path to an image file
---@param spec string crop geometry `WIDTHxHEIGHT+X+Y`, validated first
---@param out string absolute destination path
---@param opts { fit?: string }|nil `fit` is a `-resize` geometry applied after the crop
---@param on_done fun(out_path: string|nil, err: string|nil)|nil
---@return nil
function M.crop(path, spec, out, opts, on_done)
  opts = opts or {}
  local function done(out_path, err)
    if on_done then on_done(out_path, err) end
  end

  if not M.valid_crop(spec) then return done(nil, ("not a rectangle: %q -- try 800x600+10+20"):format(tostring(spec))) end
  if opts.fit ~= nil and not M.valid_geometry(opts.fit) then return done(nil, ("not a size: %q"):format(tostring(opts.fit))) end
  if type(out) ~= "string" or out == "" then return done(nil, "no destination given") end

  local ok, err = precheck(path)
  if not ok then return done(nil, err) end

  vim.fn.mkdir(vim.fs.dirname(out), "p")

  local args = { "magick", path, "-crop", spec, "+repage" }
  if opts.fit then
    args[#args + 1] = "-resize"
    args[#args + 1] = opts.fit
  end
  args[#args + 1] = out

  run_magick(args, out, "crop", on_done)
end

--- Formats `M.to_format` accepts as a target.
---
--- Derived from the configured `extensions` rather than hardcoded, so a user
--- who adds a format to display also gets it here — minus `svg`, because
--- "convert a raster image to SVG" produces an SVG wrapper around the same
--- pixels rather than anything vector, and plus `pdf`, which is the one target
--- this plugin already knew how to write.
---@return string[]
function M.target_formats()
  local out = { "pdf" }
  for _, ext in ipairs(require("images.config").get().extensions) do
    if ext:lower() ~= "svg" then out[#out + 1] = ext:lower() end
  end
  table.sort(out)
  return out
end

--- Write a resized copy next to the source ("photo.png" -> "photo.scaled.png").
---
--- `spec` is an ImageMagick geometry, validated by `M.valid_geometry` first.
--- An existing target is overwritten, so scaling the same source twice keeps
--- one result rather than accumulating `.scaled.scaled.` chains.
---@param path string absolute path to an image file
---@param spec string geometry: "50%", "800x600", "800x", "x600", "800x600!" or "800"
---@param on_done fun(out_path: string|nil, err: string|nil)|nil
---@return nil
function M.resize(path, spec, on_done)
  local function done(out_path, err)
    if on_done then on_done(out_path, err) end
  end

  if not M.valid_geometry(spec) then
    return done(nil, ("not a size: %q — try 50%%, 800x600, 800x, x600 or 800x600!"):format(tostring(spec)))
  end

  local ok, err = precheck(path)
  if not ok then return done(nil, err) end

  local ext = vim.fn.fnamemodify(path, ":e")
  local out = vim.fn.fnamemodify(path, ":r") .. ".scaled." .. (ext ~= "" and ext or "png")

  run_magick({ "magick", path, "-resize", spec, out }, out, "resize", on_done)
end

--- Write a smaller copy next to the source ("photo.png" -> "photo.optimised.png").
---
--- Two things happen: metadata is stripped (`-strip` — camera EXIF, colour
--- profiles, and on a screenshot the window title, which is the one nobody
--- thinks about before attaching it to a ticket), and PNG gets ImageMagick's
--- highest compression level. Pixel-lossless for PNG. JPEG is re-encoded
--- whatever happens, since there is no way to strip a JPEG's metadata through
--- `magick` without decoding it; without `quality` ImageMagick carries the
--- source's own quality setting over, which keeps that re-encode as close to a
--- no-op as the format allows.
---
--- **A result that is not smaller is deleted rather than kept.** `optimise`
--- is asked for by someone who wants a smaller file; handing them a larger one
--- and calling it success would be a lie, and leaving it on disk next to the
--- original is clutter they then have to clean up. The callback reports both
--- sizes either way.
---@param path string absolute path to an image file
---@param opts { quality?: integer }|nil  quality 1-100 for lossy formats; omitted = keep the source's
---@param on_done fun(out_path: string|nil, err: string|nil, before: integer|nil, after: integer|nil)|nil
---@return nil
function M.optimise(path, opts, on_done)
  opts = opts or {}

  local function done(out_path, err, before, after)
    if on_done then on_done(out_path, err, before, after) end
  end

  if opts.quality ~= nil then
    local q = tonumber(opts.quality)
    if not q or q < 1 or q > 100 then
      return done(nil, ("quality must be between 1 and 100, got %q"):format(tostring(opts.quality)))
    end
  end

  local ok, err = precheck(path)
  if not ok then return done(nil, err) end

  local stat = vim.uv.fs_stat(path)
  local before = stat and stat.size or 0

  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  local out = vim.fn.fnamemodify(path, ":r") .. ".optimised." .. (ext ~= "" and ext or "png")

  local args = { "magick", path, "-strip" }
  if ext == "png" then
    -- The one format-specific setting worth carrying: PNG's compression level
    -- is lossless by definition, so turning it to maximum costs nothing but
    -- CPU. Everything else gets `-strip` alone.
    args[#args + 1] = "-define"
    args[#args + 1] = "png:compression-level=9"
  end
  if opts.quality then
    args[#args + 1] = "-quality"
    args[#args + 1] = tostring(opts.quality)
  end
  args[#args + 1] = out

  run_magick(args, out, "optimise", function(out_path, run_err)
    if not out_path then return done(nil, run_err, before, nil) end

    local after_stat = vim.uv.fs_stat(out_path)
    local after = after_stat and after_stat.size or 0
    if after >= before then
      pcall(vim.uv.fs_unlink, out_path)
      return done(nil, nil, before, after)
    end
    done(out_path, nil, before, after)
  end)
end

--- Write a copy in a different format, on the same stem ("photo.jpg" ->
--- "photo.png").
---
--- `pdf` is routed through `M.to_pdf` rather than reimplemented: that path
--- already prefers `pdfport.nvim`'s lossless `img2pdf` when it is installed,
--- and having two ways to make a PDF that behave differently would be exactly
--- the kind of drift this plugin's docs keep warning about.
---@param path string absolute path to an image file
---@param format string target extension without the dot, see `M.target_formats`
---@param on_done fun(out_path: string|nil, err: string|nil)|nil
---@return nil
function M.to_format(path, format, on_done)
  local function done(out_path, err)
    if on_done then on_done(out_path, err) end
  end

  if type(format) ~= "string" or format == "" then return done(nil, "no target format given") end
  format = format:lower():gsub("^%.", "")

  if format == "pdf" then
    return M.to_pdf(path, function(ok_pdf, out_or_err)
      if ok_pdf then
        done(out_or_err, nil)
      else
        done(nil, out_or_err)
      end
    end)
  end

  local ok, err = precheck(path)
  if not ok then return done(nil, err) end

  local out = vim.fn.fnamemodify(path, ":r") .. "." .. format
  -- Same file, spelled two ways ("photo.PNG" asked to become "png"): magick
  -- would happily read and rewrite it, which is an in-place edit of the
  -- source — the one thing none of these operations does.
  if require("images.resolve").normalize_path(out):lower() == require("images.resolve").normalize_path(path):lower() then
    return done(nil, ("%s is already %s"):format(vim.fn.fnamemodify(path, ":t"), format))
  end

  run_magick({ "magick", path, out }, out, "conversion", on_done)
end

return M
