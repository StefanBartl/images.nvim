---@module 'images.health'
---@brief `:checkhealth images`

local M = {}

--- An info line with the advice `vim.health.info` has no parameter for.
---
--- `warn` and `error` take advice as varargs and render it under the message;
--- `info` takes the message and nothing else, so a second argument is dropped
--- on the floor -- the three tesseract install hints below never reached a
--- `:checkhealth`. They are rendered into the message here instead, in the
--- shape `vim.health` gives a warning's advice, so both lines read alike.
---@param msg string
---@param advice string[]|nil rendered under the message, one line each
---@return nil
local function h_info(msg, advice)
  if advice and #advice > 0 then msg = msg .. "\n- ADVICE:\n  - " .. table.concat(advice, "\n  - ") end
  vim.health.info(msg)
end

---@return nil
local function check_output()
  if vim.api.nvim_ui_send then
    vim.health.ok("`nvim_ui_send` available — images can be drawn")
  else
    vim.health.error(
      "`nvim_ui_send` is missing (requires API level 14)",
      { "update Neovim — without this API no image can be drawn" }
    )
  end
end

---@return nil
local function check_terminal()
  -- The same check that runs before drawing — a second heuristic here would
  -- only drift apart from it.
  local cap = require("images.terminal").capability(false)

  if cap.ok and cap.terminal then
    vim.health.ok(("`%s` detected — OSC 1337 is supported"):format(cap.terminal))
  elseif cap.ok then
    vim.health.warn("support is being assumed (`display.assume_supported`)")
  else
    vim.health.warn(cap.reason or "terminal not recognised", {
      cap.hint or "",
      "images.nvim needs a terminal that speaks the iTerm2 protocol (OSC 1337).",
    })
  end

  if cap.hint and cap.ok then vim.health.warn(cap.hint) end
end

---@return nil
local function check_clipboard()
  local executable = require("lib.nvim.cross.executable")

  if require("lib.nvim.cross.platform.is_windows")() then
    if executable.exists("powershell.exe") then
      vim.health.ok("`powershell.exe` found — `:Image paste` available")
    else
      vim.health.warn("`powershell.exe` not found — `:Image paste` will not work")
    end
    return
  end

  if require("lib.nvim.cross.platform.is_macos")() then
    if executable.exists("pngpaste") then
      vim.health.ok("`pngpaste` found — `:Image paste` available")
    else
      vim.health.warn("`pngpaste` is missing", { "brew install pngpaste" })
    end
    return
  end

  if executable.exists("wl-paste") then
    vim.health.ok("`wl-paste` found — `:Image paste` available")
  elseif executable.exists("xclip") then
    vim.health.ok("`xclip` found — `:Image paste` available")
  else
    vim.health.warn("neither `wl-paste` nor `xclip` found — `:Image paste` will not work")
  end
end

---@return nil
local function check_screenshot()
  local screenshot = require("images.screenshot")
  if screenshot.available() then
    if require("lib.nvim.cross.platform.is_windows")() then
      vim.health.ok("Snipping Tool (`ms-screenclip:`) available — `:Image screenshot`")
    else
      vim.health.ok("`:Image screenshot` available")
    end
  else
    -- info rather than warn: :Image paste remains the unchanged route, and
    -- without screenshot-capable tools only that one extra command is missing.
    vim.health.info(screenshot.unavailable_reason() .. " — `:Image screenshot` stays off, `:Image paste` keeps working")
  end
end

---@return nil
local function check_imagemagick()
  if require("lib.nvim.cross.executable").exists("magick") then
    vim.health.ok(
      "`magick` found — `:Image info` dimensions, `:Image compare`'s relative scaling, SVG display, `:Image export`, `:Image redact`, `:Image scale`, `:Image optimise` and `:Image convert` available"
    )
  else
    -- Not `vim.health.warn`: ImageMagick improves info/compare/SVG but is not a
    -- prerequisite for them (a deliberate guardrail) --
    -- `info` merely lacks the dimensions, `compare` shows both images at the
    -- same size, and SVGs report a clear error when drawn rather than failing
    -- silently. `:Image export`/`redact` and the three file operations
    -- (`scale`/`optimise`/`convert`) are the explicit exception to that
    -- guardrail: all of them run exclusively through `magick`, with no
    -- fallback -- an image operation without an image library is not a
    -- degraded feature, it is no feature.
    vim.health.info(
      "`magick` not found — `:Image info` dimensions, `:Image compare`'s relative scaling and SVG display stay off; everything else works (except `:Image export`/`redact`/`scale`/`optimise`/`convert`, which require `magick`)"
    )
  end
end

---@return nil
local function check_ocr()
  local ocr = require("images.ocr")
  local bin = ocr.bin()
  if not bin then
    h_info("`tesseract` not found — `:Image ocr` stays off; nothing else is affected", {
      "winget install UB-Mannheim.TesseractOCR  (Windows)",
      "apt install tesseract-ocr  /  brew install tesseract",
      "installed somewhere unusual? set `ocr.bin` to its path",
    })
    return
  end

  -- The path is worth printing rather than a bare "found": on Windows this is
  -- routinely the well-known-directory probe rather than PATH (see
  -- images.ocr), and "found" alone would hide that the shell still cannot run
  -- `tesseract` -- which is exactly the confusion the probe exists to defuse.
  vim.health.ok(("`%s` found — `:Image ocr` available"):format(bin))

  local langs = ocr.languages()
  if #langs == 0 then
    vim.health.warn("tesseract reports no language data — `:Image ocr` will fail on every image", {
      "the language packages install separately from the binary",
      "apt install tesseract-ocr-deu  /  brew install tesseract-lang",
    })
    return
  end

  local configured = require("images.config").get().ocr.lang
  vim.health.info(("language data installed: %s"):format(table.concat(langs, ", ")))

  -- `ocr.lang` may name several at once ("deu+eng"), so each part is checked
  -- on its own -- a single missing half fails the whole call in tesseract.
  local missing = {}
  for _, part in ipairs(vim.split(configured or "eng", "+", { plain = true, trimempty = true })) do
    if not vim.tbl_contains(langs, part) then missing[#missing + 1] = part end
  end
  if #missing > 0 then
    vim.health.warn(("`ocr.lang` = %q, but %s is not installed"):format(configured, table.concat(missing, ", ")), {
      "install the missing language data, or set `ocr.lang` to one of the above",
    })
  else
    vim.health.ok(("`ocr.lang` = %q — installed"):format(configured))
  end
end

---Whether a PDF entry can be drawn as a page (`images.pdf`, consumed by
---`images.integrations.picker`). Three separate states with three separate
---fixes -- switched off, pdfport.nvim missing, poppler missing -- so they are
---reported separately rather than as one "unavailable".
---@return nil
local function check_pdf()
  local cfg = require("images.config").get()
  if (cfg.pdf or {}).enabled == false then
    vim.health.info("PDF pages: switched off in setup() — `pdf = { enabled = false }`")
    return
  end

  local ok_pdfport, pdfport = pcall(require, "pdfport")
  if not ok_pdfport or type(pdfport.render_page) ~= "function" then
    vim.health.info("`pdfport.nvim` not present — a PDF entry keeps a host's own preview", {
      "https://github.com/StefanBartl/pdfport.nvim draws its first page instead",
    })
    return
  end

  if not require("lib.nvim.cross.executable").exists("pdftoppm") then
    vim.health.warn("`pdftoppm` not found — pdfport.nvim is installed but cannot rasterize", {
      "apt install poppler-utils  /  brew install poppler  /  scoop install poppler",
    })
    return
  end

  vim.health.ok(
    ("`pdfport.nvim` + `pdftoppm` found — a PDF previews as page %d at %d dpi"):format(
      require("images.pdf").page(),
      require("images.pdf").dpi()
    )
  )
end

---@return nil
local function check_deps()
  if pcall(require, "lib.nvim.bindings.usercmd.composer") then
    vim.health.ok("`lib.nvim` found")
  else
    vim.health.error("`lib.nvim` is missing", { "add StefanBartl/lib.nvim as a dependency" })
  end

  if pcall(require, "markdown.util.path") then
    vim.health.ok("`markdown.nvim` found — its path resolver will be used")
  else
    vim.health.info("`markdown.nvim` not present — the internal path resolution will be used")
  end
end

---@return nil
---Reports images.nvim's own docs/install.json through lib.nvim.deps -- the same
---tools check_imagemagick()/check_clipboard() already cover, but with the
---declared `why` per tool and a pointer to `:Lib deps show`. Does nothing when
---lib.nvim.deps is absent (an older lib.nvim).
local function check_lib_deps()
  local ok, deps_health = pcall(require, "lib.nvim.deps.health")
  if not ok then return end
  vim.health.start("images.nvim: declared tools (lib.nvim.deps)")
  deps_health.report_for("images.nvim")
end

---@return nil
function M.check()
  vim.health.start("images.nvim")
  check_output()
  check_terminal()
  check_clipboard()
  check_screenshot()
  check_imagemagick()
  check_ocr()
  check_pdf()
  check_deps()
  check_lib_deps()
end

return M
