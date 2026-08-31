---@module 'images.ocr'
---@brief Read the text out of an image, via `tesseract`.
---@description
--- The same shape as `images.convert`: an external binary, an argv array, an
--- asynchronous `vim.system`, a result handed to a callback. Nothing about OCR
--- justifies a different structure, and `convert.lua`'s error handling is the
--- one this needs too.
---
--- **Why this is not an interface to `language.nvim`.** The roadmap entry that
--- asked for this ("OCR crossed with language.nvim") anticipated a bridge
--- between two plugins. There is nothing to bridge: every public entry point of
--- `language.translate` is buffer-bound (`run_region` wants a `bufnr` plus
--- coordinates). Put the recognised text into a buffer — which is what you want
--- anyway, to read, correct and copy it — and `:Translate` on a Visual
--- selection already *is* the crossing, through keys that exist. So this module
--- does OCR and nothing else, and stops where a buffer begins.
---
--- **Output goes to stdout, not to a file.** `tesseract in out` writes
--- `out.txt`; `tesseract in stdout` writes to stdout. The second form needs no
--- temporary file, no cleanup and no guess at a writable directory — and unlike
--- `convert.to_pdf`/`redact` there is no artefact anyone wants to keep here.
--- What is worth keeping is the text, and the caller decides where that lands.
---
--- **SVG goes through `images.convert` first.** tesseract reads what leptonica
--- reads, and that is raster formats only. Since `to_png` exists, is cached and
--- is already the plugin's answer to "this is an SVG", reusing it costs one
--- branch and makes `:Image ocr` work on the same set of files as every other
--- route.

local M = {}

--- Directories probed for `tesseract` when it is not on PATH.
---
--- Not a general habit — every other external tool in this plugin (`magick`,
--- `chafa`, `wl-paste`) is looked up on PATH and nowhere else. tesseract earns
--- the exception because its Windows installer earns it: the UB-Mannheim build
--- named in `docs/install.json` leaves "Add to PATH" unticked, so on Windows
--- "installed" and "reachable" routinely come apart, and the failure looks
--- exactly like "not installed" to anyone who just ran the installer. Two
--- `fs_stat` calls, only ever reached when PATH has already come up empty, are
--- cheaper than that confusion.
---
--- `ocr.bin` in the configuration overrides all of it — an explicit path always
--- wins over a guess.
---@type string[]
local WELL_KNOWN = {
  "C:/Program Files/Tesseract-OCR/tesseract.exe",
  "C:/Program Files (x86)/Tesseract-OCR/tesseract.exe",
}

---@type string|false|nil  false = "looked for, not found"; nil = not looked yet
local resolved_bin = nil

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Forget the memoized binary lookup, so the next call searches again.
---
--- The counterpart to `lib.nvim.cross.executable.clear`, and needed for the
--- same reason plus one of its own: this module also caches the outcome of the
--- `WELL_KNOWN` probe, which that function knows nothing about. Anything that
--- installs tesseract during a session — or changes `ocr.bin` — calls this.
---@return nil
function M.clear()
  resolved_bin = nil
  require("lib.nvim.cross.executable").clear("tesseract")
end

--- The tesseract binary to run: `ocr.bin` if configured, else PATH, else one of
--- the well-known Windows install directories. Memoized; see `M.clear`.
---@return string|nil  an executable name or absolute path, nil when none was found
function M.bin()
  if resolved_bin ~= nil then return resolved_bin or nil end

  local configured = cfg().ocr and cfg().ocr.bin
  if type(configured) == "string" and configured ~= "" then
    -- Taken as given, without a stat: a configured path is a decision, and
    -- second-guessing it here would only turn a clear "no such file" from
    -- vim.system into a vaguer one from this module.
    resolved_bin = configured
    return resolved_bin
  end

  if require("lib.nvim.cross.executable").exists("tesseract") then
    resolved_bin = "tesseract"
    return resolved_bin
  end

  for _, candidate in ipairs(WELL_KNOWN) do
    if vim.uv.fs_stat(candidate) then
      resolved_bin = candidate
      return resolved_bin
    end
  end

  resolved_bin = false
  return nil
end

--- Whether OCR can run at all.
---@return boolean
function M.available()
  return M.bin() ~= nil
end

--- The language data tesseract has installed, as passed to `-l`.
---
--- Synchronous on purpose: the only callers are `:checkhealth` and the error
--- path below, both of which are already reporting rather than working, and
--- both of which want the answer in the message they are about to print.
---@return string[] langs  empty when tesseract is missing or the call fails
function M.languages()
  local bin = M.bin()
  if not bin then return {} end

  local result = vim.system({ bin, "--list-langs" }, { text = true }):wait()
  if result.code ~= 0 then return {} end

  local langs = {}
  -- The first line is a header ("List of available languages in ..."), the
  -- rest one code per line. Filtering on the header's colon rather than
  -- skipping line 1 keeps this working if the wording ever changes.
  for _, line in ipairs(vim.split(result.stdout or "", "\r?\n", { trimempty = true })) do
    local code = vim.trim(line)
    if code ~= "" and not code:find(":") then langs[#langs + 1] = code end
  end
  table.sort(langs)
  return langs
end

--- Read the text out of an image.
---
--- Asynchronous throughout: OCR on a full-screen screenshot is a second or
--- more, and `:Image ocr` is precisely the situation where you carry on
--- reading the image while it runs — the same reasoning that made
--- `convert.redact` asynchronous.
---
--- `on_done` is the only route to the result, and is called exactly once on
--- every path, failures included.
---@param path string absolute path to an image file
---@param opts { lang?: string, args?: string[] }|nil  nil = the configured language and extra arguments
---@param on_done fun(text: string|nil, err: string|nil)
---@return nil
function M.run(path, opts, on_done)
  opts = opts or {}

  local function done(text, err)
    if on_done then on_done(text, err) end
  end

  local bin = M.bin()
  if not bin then
    return done(nil, "OCR requires tesseract (`tesseract` not found on PATH)")
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then return done(nil, "file not found: " .. path) end

  -- SVG cannot be read by tesseract; the PNG conversion is cached, so a
  -- repeated `:Image ocr` on the same SVG pays for it once.
  local input = path
  local convert = require("images.convert")
  if convert.is_svg(input) then
    local png, err = convert.to_png(input)
    if not png then return done(nil, err or "SVG could not be converted for OCR") end
    input = png
  end

  local ocr_cfg = cfg().ocr or {}
  local lang = opts.lang or ocr_cfg.lang or "eng"

  local args = { bin, input, "stdout", "-l", lang }
  for _, extra in ipairs(opts.args or ocr_cfg.args or {}) do
    args[#args + 1] = extra
  end

  vim.system(args, { text = true }, function(result)
    -- vim.system callbacks run outside the main loop; every caller's `on_done`
    -- ends up in a buffer, notify or vim.fn.
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or "")
        -- A wrong `-l` is the one failure worth translating into advice: the
        -- language data is a separate download from the binary, so "not
        -- installed" is a routine state rather than a typo, and the list of
        -- what IS installed answers the question the error raises.
        if stderr:find("Failed loading language") or stderr:find("Could not initialize tesseract") then
          local have = M.languages()
          local available = #have > 0 and table.concat(have, ", ") or "none"
          return done(nil, ("OCR language '%s' is not installed (available: %s)"):format(lang, available))
        end
        return done(nil, "OCR failed: " .. (stderr ~= "" and stderr or ("exit code " .. tostring(result.code))))
      end

      local text = vim.trim(result.stdout or "")
      if text == "" then return done(nil, "no text found in the image") end
      done(text, nil)
    end)
  end)
end

--- The recognised text as buffer lines: trailing whitespace stripped and runs
--- of blank lines collapsed to one.
---
--- tesseract pads its output generously — trailing spaces on nearly every line
--- and a blank line per detected paragraph gap, which on a screenshot of a
--- dialog box means more blank lines than text. Handing that straight to a
--- buffer makes the result look like a bad transcription when the recognition
--- was fine, and every consumer (a Visual selection for `:Translate`, a yank,
--- a `.ocr.md` written next to a case attachment) wants it cleaned anyway.
---@param text string
---@return string[]
function M.to_lines(text)
  local lines = {}
  local blank_run = false
  for _, raw in ipairs(vim.split(text, "\r?\n")) do
    local line = raw:gsub("%s+$", "")
    if line == "" then
      if not blank_run and #lines > 0 then lines[#lines + 1] = "" end
      blank_run = true
    else
      lines[#lines + 1] = line
      blank_run = false
    end
  end
  -- A collapsed run at the very end leaves one trailing blank line behind.
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return lines
end

return M
