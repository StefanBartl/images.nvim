---@module 'images.pdf'
---@brief A page of a PDF as a PNG, via pdfport.nvim — cached on disk, so a
---page is rasterized once per file version and drawn from then on.
---@description
--- images.nvim draws pictures; it does not read PDFs, and it does not want to.
--- What it needs to show a page is a PNG of that page, and
--- [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) already
--- produces exactly that through `pdfport.render_page` (poppler's `pdftoppm`
--- underneath). This module is the whole of the seam between the two: it turns
--- a path into a PNG path and caches the result. Everything above it — the
--- picker preview surface, the draw, the overlay's lifetime — carries on
--- treating the page as an ordinary image file, because by then it is one.
---
--- The same division already runs the other way round: `images.convert.to_pdf`
--- hands an image to pdfport to *make* a PDF. Neither plugin depends on the
--- other; both check by shape and step aside when the other is absent.
---
--- **Why the cache is on disk and outlives the session.** It mirrors the SVG
--- cache in `images.convert` exactly — same directory root, same
--- sha256-of-path-plus-mtime key — for the same two reasons. The expensive
--- part is a process start plus a rasterization (150–400 ms for a dense A4
--- page), not the draw; and the mtime in the key already makes a kept file
--- safe to serve, because an edited PDF has a different key and rasterizes
--- again. A picker preview is the case this was built for, and it is the case
--- that punishes an in-memory cache hardest: moving down a list and back up is
--- the normal way to use a picker, and every session starts by moving down a
--- list.
---
--- **Two requests for the same page produce one `pdftoppm`.** Selection in a
--- picker moves faster than a rasterizer runs, and the second request for a
--- page arrives while the first is still out. It joins the first instead of
--- starting a second process over the same output path.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

---@return ImagesNvim.PdfConfig
local function pdf_cfg()
  return cfg().pdf or {}
end

--- Whether a path names a PDF, by extension alone — the same cheap judgement
--- `images.resolve.is_image` makes, and cheap for the same reason: a host
--- calls it once per entry while the selection moves.
---@param path string|nil
---@return boolean
function M.is_pdf(path)
  if type(path) ~= "string" or path == "" then return false end
  return (path:match("%.([%w]+)%s*$") or ""):lower() == "pdf"
end

--- Whether a page could be produced right now: switched on, pdfport.nvim
--- installed and exposing `render_page`, and poppler's `pdftoppm` on PATH.
---
--- `pdftoppm` is checked here rather than left to pdfport's own error, because
--- the answer decides whether images.nvim claims a PDF *at all*. A claim it
--- cannot honour costs a host its own working preview — see
--- `images.integrations.picker`, where that reasoning is spelled out in full.
---@return boolean
function M.available()
  if pdf_cfg().enabled == false then return false end

  local ok, pdfport = pcall(require, "pdfport")
  if not ok or type(pdfport) ~= "table" or type(pdfport.render_page) ~= "function" then return false end

  return require("lib.nvim.cross.executable").exists("pdftoppm")
end

--- The page rasterized when a caller names none.
---@return integer
function M.page()
  local page = pdf_cfg().page
  return type(page) == "number" and page >= 1 and math.floor(page) or 1
end

--- The resolution a page is rasterized at when a caller names none.
---@return integer
function M.dpi()
  local dpi = pdf_cfg().dpi
  return type(dpi) == "number" and dpi >= 1 and math.floor(dpi) or 120
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/pdf"
  require("lib.nvim.fs.mkdirp")(dir)
  return dir
end

--- The cache file name for one rasterization, without directory or extension.
---
--- A pure function, and public, so the key is assertable without poppler
--- installed and without a PDF — the same reason `pdfport.core.rasterize.args`
--- is one. What has to hold is that all four inputs reach the key: a page, a
--- resolution and a file *version* each produce a different picture, and two
--- of them sharing a name would serve the wrong one for as long as the cache
--- lives, which is forever.
---@param path string
---@param mtime integer seconds
---@param page integer
---@param dpi integer
---@return string
function M.cache_key(path, mtime, page, dpi)
  return vim.fn.sha256(table.concat({ path, tostring(mtime), tostring(page), tostring(dpi) }, ":"))
end

--- Where the PNG for this page lives, whether or not it exists yet.
---@param path string
---@param page integer
---@param dpi integer
---@return string|nil out
---@return string|nil err
function M.cache_file(path, page, dpi)
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "file not found: " .. path end
  local key = M.cache_key(path, stat.mtime and stat.mtime.sec or 0, page, dpi)
  return cache_dir() .. "/" .. key .. ".png"
end

---@type table<string, (fun(png: string|nil, err: string|nil))[]> keyed by output path
local inflight = {}

---@class Images.Pdf.PageOpts
---@field page integer|nil 1-based; default `pdf.page`
---@field dpi integer|nil default `pdf.dpi`

--- A PNG of one page of `path`.
---
--- **The callback may run synchronously** — that is the cache hit, and it is
--- the common case once a page has been looked at once. Callers that need a
--- deferred draw defer the draw, not this call; `images.draw` already does.
---@param path string absolute path to a .pdf file
---@param opts Images.Pdf.PageOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil runs exactly once
---@return nil
function M.page_png(path, opts, callback)
  opts = opts or {}

  if not M.is_pdf(path) then
    callback(nil, "not a PDF: " .. tostring(path))
    return
  end
  if not M.available() then
    callback(nil, "a PDF page needs pdfport.nvim and poppler's pdftoppm")
    return
  end

  local page = opts.page or M.page()
  local dpi = opts.dpi or M.dpi()

  local out, err = M.cache_file(path, page, dpi)
  if not out then
    callback(nil, err)
    return
  end
  if vim.uv.fs_stat(out) then
    callback(out, nil)
    return
  end

  local waiting = inflight[out]
  if waiting then
    waiting[#waiting + 1] = callback
    return
  end
  inflight[out] = { callback }

  -- `output_path` rather than pdfport's tempname: the cache *is* the
  -- destination, so there is nothing to move afterwards and nothing to clean
  -- up on a caller's behalf. pdfport strips the `.png` again before handing
  -- the base to pdftoppm, which appends it back.
  require("pdfport").render_page(path, page, { dpi = dpi, output_path = out }, function(png, rerr)
    local waiters = inflight[out] or {}
    inflight[out] = nil
    for _, cb in ipairs(waiters) do
      cb(png, rerr)
    end
  end)
end

return M
