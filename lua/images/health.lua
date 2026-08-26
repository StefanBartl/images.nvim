---@module 'images.health'
---@brief `:checkhealth images`

local M = {}

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
      "`magick` found — `:Image info` dimensions, `:Image compare`'s relative scaling, SVG display, `:Image export` and `:Image redact` available"
    )
  else
    -- Not `vim.health.warn`: ImageMagick improves info/compare/SVG but is not a
    -- prerequisite for them (see the guardrail in docs/ROADMAP/README.md) --
    -- `info` merely lacks the dimensions, `compare` shows both images at the
    -- same size, and SVGs report a clear error when drawn rather than failing
    -- silently. `:Image export`/`redact` are the explicit exception to that
    -- guardrail: both run exclusively through `magick`, with no fallback.
    vim.health.info(
      "`magick` not found — `:Image info` dimensions, `:Image compare`'s relative scaling and SVG display stay off; everything else works (except `:Image export`/`redact`, which require `magick`)"
    )
  end
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
  check_deps()
  check_lib_deps()
end

return M
