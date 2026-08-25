---@module 'images.resolve'
---@brief Find image targets in the buffer and resolve them to absolute paths.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Whether a target looks like an image file (by extension alone).
---@param target string
---@return boolean
function M.is_image(target)
  local ext = target:match("%.([%w]+)%s*$") or target:match("%.([%w]+)[?#]")
  if not ext then return false end
  ext = ext:lower()
  for _, e in ipairs(cfg().extensions) do
    if e == ext then return true end
  end
  return false
end

--- Every link target on a line, with its column range (1-based, both bounds
--- inclusive).
---
--- Prefers markdown.nvim's scanner, which understands raw HTML alongside
--- `![alt](target)` — `<img src="…">` inside a `<figure>` block is exactly the
--- pattern that gives a caption in Markdown, and without this delegation every
--- captioned image would be invisible to `:Image`. Without markdown.nvim the
--- built-in Markdown pattern stands.
---@param line string
---@param lnum integer|nil only relevant for passing on to markdown.nvim
---@return { target: string, from: integer, to: integer }[]
function M.links_in_line(line, lnum)
  local ok, scan = pcall(require, "markdown.core.link_scan")
  if ok and type(scan.from_line) == "function" then
    local out = {}
    for _, link in ipairs(scan.from_line(line, lnum or 1)) do
      out[#out + 1] = { target = link.target, from = link.col + 1, to = link.col_end + 1 }
    end
    return out
  end

  local out = {}
  local init = 1
  while true do
    local s, e, target = line:find("%]%(([^)]+)%)", init)
    if not s then break end
    -- Start of the link including `![alt` or `[text`, so that the cursor may
    -- sit anywhere in the link rather than only inside the parentheses.
    local from = line:sub(1, s):find("!?%[[^%[]*$") or s
    out[#out + 1] = { target = target, from = from, to = e }
    init = e + 1
  end
  return out
end

--- Normalise a path: consistently `/` rather than a mix of `/` and `\`.
---
--- `fnamemodify(p, ":p")` does not normalise consistently on Windows — a path
--- assembled with `/` came back in testing as `C:\...\0/assets\a.png`, slash
--- and backslash mixed within the same string. For `io.open`/`nvim_ui_send`
--- that is immaterial, Windows accepts both; as a key in a string set (see
--- `images.orphans`, which deduplicates compared paths exactly that way) it
--- turns two genuinely identical files into two different strings.
---@param p string
---@return string
local function normalize(p)
  local ok, utils = pcall(require, "lib.nvim.normalize.utils")
  if ok and utils.normalize_path then return utils.normalize_path(p) end
  return (p:gsub("\\", "/"))
end
M.normalize_path = normalize

--- Resolve a relative path. Uses markdown.nvim's resolver when present — it
--- already knows several base directories and normalises Windows paths
--- correctly. Otherwise the buffer's directory, then cwd.
---@param target string
---@param buf integer|nil buffer whose directory to resolve against
---@return string|nil absolute path, if the file exists
function M.to_path(target, buf)
  if target:match("^%a+://") then
    return nil -- remote URLs are not downloaded (yet)
  end

  local ok, path_util = pcall(require, "markdown.util.path")
  if ok and type(path_util.resolve) == "function" then
    local resolved = path_util.resolve(target)
    if resolved and vim.uv.fs_stat(resolved) then return normalize(resolved) end
  end

  -- Deliberately not `vim.fn.expand`. `target` is link text read out of a
  -- Markdown buffer, and a backtick span in vim.fn.expand's argument is a
  -- *command substitution* run through `&shell` -- so
  -- `![x](`mkdir /tmp/pwned; echo a.png#`)` executed on resolve. Confirmed:
  -- the directory appeared. The trailing `#` is what got it past is_image,
  -- whose second alternative matches an extension anywhere before a `?`/`#`.
  -- Only `~` and environment variables are wanted here, which is all
  -- expand_path does.
  local expanded = require("lib.nvim.cross.fs.expand_path")(target)
  if vim.uv.fs_stat(expanded) then return normalize(vim.fn.fnamemodify(expanded, ":p")) end

  local bases = {}
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name ~= "" then bases[#bases + 1] = vim.fn.fnamemodify(name, ":p:h") end
  bases[#bases + 1] = vim.uv.cwd()

  for _, base in ipairs(bases) do
    if base and base ~= "" then
      local candidate = base .. "/" .. expanded
      if vim.uv.fs_stat(candidate) then return normalize(vim.fn.fnamemodify(candidate, ":p")) end
    end
  end
  return nil
end

--- Resolve a raw target (link text or `<cfile>`) into a `Target`.
---
--- A remote URL is NOT downloaded here — `path` is then simply the URL itself.
--- The download happens later in `images.init.M.show`, the one place where a
--- single image is actually drawn (see `images.remote`'s module docs for the
--- reason: resolving must never trigger network requests unasked, only
--- displaying may).
---@param raw string
---@param lnum integer
---@return ImagesNvim.Target|nil
---@return string|nil err
local function resolve_target(raw, lnum)
  if not M.is_image(raw) then return nil, "not an image target: " .. raw end
  if require("images.remote").is_remote(raw) then return { raw = raw, path = raw, lnum = lnum } end
  local path = M.to_path(raw)
  if not path then return nil, "image not found: " .. raw end
  return { raw = raw, path = path, lnum = lnum }
end

--- Image target under the cursor: the line's Markdown links first, otherwise
--- `<cfile>`.
---@return ImagesNvim.Target|nil
---@return string|nil err
function M.under_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1], pos[2] + 1
  local line = vim.api.nvim_get_current_line()

  for _, link in ipairs(M.links_in_line(line, lnum)) do
    if col >= link.from and col <= link.to then return resolve_target(link.target, lnum) end
  end

  -- Cursor inside a `<figure>` block but not on the `<img>` itself (typically
  -- on the `<figcaption>` line): markdown.nvim resolves the block as a whole,
  -- so the caption refers to the same image as the tag above it.
  local ok_html, html = pcall(require, "markdown.core.html_links")
  if ok_html and type(html.figure_at) == "function" then
    local fig = html.figure_at(vim.api.nvim_get_current_buf(), lnum)
    if fig then return resolve_target(fig.target, lnum) end
  end

  local cfile = vim.fn.expand("<cfile>")
  if cfile == "" then return nil, "no link or file name under the cursor" end
  return resolve_target(cfile, lnum)
end

--- Resolve `path`, or the image under the cursor when it is `nil` — the same
--- pattern `:Image replace`, `:Image zen` and `:Image export` all need
--- ("explicit path or cursor target"), in one place rather than duplicated
--- three times.
---@param path string|nil
---@return string|nil absolute path
function M.path_or_cursor(path)
  if path then return M.to_path(path) end
  local target = M.under_cursor()
  return target and target.path
end

return M
