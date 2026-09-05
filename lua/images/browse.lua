---@module 'images.browse'
---@brief Find images in a directory tree and pick one with a live preview.
---@description
--- Unlike `images.scan` (image links in *one buffer*) this module searches the
--- filesystem itself: every image file below a root, linked or not. Three
--- scopes resolve that root — `cfile` (the current file's directory), `cwd`,
--- and `path <dir>` (explicit).
---
--- No dependency on pickers.nvim, though the reason has changed shape since
--- this was written. It used to be that no engine-neutral abstraction could
--- carry a plugin's own live preview across telescope/fzf-lua/snacks; that is
--- no longer true — pickers.nvim draws image entries in its own pickers by
--- consuming `images.integrations.picker` (snacks and telescope; see
--- docs/FEATURES/INTEGRATIONS.md). What it does not carry is this module's own
--- extra: `<Tab>` multi-select whose confirm turns several images into a
--- gallery instead of one display, which lives in the snacks `confirm` handler
--- below. So the direct binding to `snacks.picker` stays (a soft dependency,
--- the same pattern as the guarded which-key probe elsewhere here), falling
--- back to a plain selection without preview when snacks is absent — and the
--- two features sit side by side rather than one replacing the other:
--- `:Image pickers` is the image browser, pickers.nvim previews images on the
--- way past.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- Directory names always skipped — independent of `display.browse_exclude`,
--- which the user can extend on top.
---@type table<string, boolean>
local ALWAYS_EXCLUDE = { [".git"] = true }

--- Upper bound on visited entries, as a safety net against a huge `cwd` scan
--- (e.g. accidentally started in the home directory). Not an error, just a
--- quiet stop — the results found so far are still useful.
---@return integer
local function max_entries()
  local ok, config = pcall(require, "images.config")
  if not ok or type(config.get) ~= "function" then return 20000 end
  local n = ((config.get() or {}).display or {}).browse_max_entries
  return (type(n) == "number" and n > 0) and n or 20000
end

--- Collect image files below `root` (breadth-first, iterative rather than
--- recursive — avoids stack depth on deeply nested trees).
---@param root string absolute path
---@param exclude string[]|nil additional directory names to skip
---@param extensions string[] permitted extensions, without the dot
---@return string[] image paths found, sorted
local function walk(root, exclude, extensions)
  local exclude_set = vim.deepcopy(ALWAYS_EXCLUDE)
  for _, name in ipairs(exclude or {}) do
    exclude_set[name] = true
  end

  local ext_set = {}
  for _, e in ipairs(extensions) do
    ext_set[e:lower()] = true
  end

  local found = {}
  local visited = 0
  local stack = { root }

  while #stack > 0 do
    local dir = table.remove(stack)
    local handle = vim.uv.fs_scandir(dir)
    if handle then
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then break end
        visited = visited + 1
        if visited > max_entries() then
          table.sort(found)
          return found
        end
        if kind == "directory" then
          if not exclude_set[name] then stack[#stack + 1] = dir .. "/" .. name end
        elseif kind == "file" then
          local ext = name:match("%.([%w]+)$")
          if ext and ext_set[ext:lower()] then found[#found + 1] = dir .. "/" .. name end
        end
      end
    end
  end

  table.sort(found)
  return found
end
-- Exposed for tests: a pure function, no terminal required.
M.walk = walk

--- Collect image files below `root`, using the configured exclusion list and
--- the configured extensions.
---@param root string absolute directory path
---@return string[] absolute paths, sorted
function M.scan(root)
  local c = cfg()
  return walk(root, c.display.browse_exclude, c.extensions)
end

--- Resolve the scope argument to a single root directory.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil for scope="path": the target directory
---@return string|nil root normalised (see `images.resolve.normalize_path`)
---@return string|nil err
function M.roots(scope, arg)
  scope = scope or "cwd"
  local resolve = require("images.resolve")

  if scope == "path" then
    if not arg or arg == "" then return nil, "the `path` scope needs a directory: :Image pickers path <dir>" end
    local expanded = vim.fn.fnamemodify(vim.fn.expand(arg), ":p")
    if vim.fn.isdirectory(expanded) == 0 then return nil, "not a directory: " .. arg end
    return resolve.normalize_path(expanded)
  end

  if scope == "cfile" then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then return nil, "the current buffer has no file path" end
    return resolve.normalize_path(vim.fn.fnamemodify(name, ":p:h"))
  end

  if scope == "cwd" then return resolve.normalize_path(vim.uv.cwd() or vim.fn.getcwd()) end

  return nil, "unknown scope: " .. tostring(scope) .. " (expected cfile|cwd|path)"
end

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

---@return table|nil # snacks.picker, if installed
local function snacks_picker()
  local ok, picker = pcall(require, "snacks.picker")
  return (ok and type(picker) == "table") and picker or nil
end

--- Whether `snacks.picker` is available — for `:checkhealth images`.
---@return boolean
function M.snacks_available()
  return snacks_picker() ~= nil
end

--- Draw an image against a window's geometry rather than the cursor position
--- (unlike `images.show`) — for the preview inside a picker window whose
--- location the caller does not know itself.
---
--- A thin wrapper around `images.anchor.draw` (the canonical implementation);
--- name and signature stay unchanged because markdown.nvim already consumes
--- this function as public API. A new consumer should call `images.draw()`
--- directly instead -- see docs/FEATURES/INTEGRATIONS.md.
---@param file string
---@param winid integer
---@param factor number|nil 0 < factor <= 1; nil/1 = the full window size.
---            Below 1 centres a correspondingly smaller box inside the window
---            instead of filling it — see `images.scale`, which derives the
---            factor from the real image dimensions for `:Image compare`.
---@return boolean ok
local function draw_in_window(file, winid, factor)
  local position = (factor and factor < 1) and "center" or "full"
  local ok = require("images.anchor").draw(winid, position, file, { scale = factor })
  return ok
end
M.draw_in_window = draw_in_window

--- Open a picker with a live image preview via `snacks.picker`.
---@param root string
---@param files string[]
local function open_snacks(root, files)
  local Picker = snacks_picker()
  if not Picker then
    notify().error("snacks.picker is not available")
    return
  end

  local items = {}
  for i, path in ipairs(files) do
    items[i] = { text = path, file = path }
  end

  Picker.pick({
    source = "images_browse",
    title = "Images: " .. root,
    items = items,
    format = "file",
    preview = function(ctx)
      ctx.preview:reset()
      if not draw_in_window(ctx.item.file, ctx.win) then ctx.preview:notify("the image cannot be drawn here", "warn") end
    end,
    -- `<Tab>` is snacks' own multi-select key (not wired up by images.nvim).
    -- `picker:selected({fallback=true})` returns the marked results, or — with
    -- nothing marked — the single highlighted one: several images make a
    -- gallery, one makes the ordinary single display.
    confirm = function(picker, item)
      local selected = picker:selected({ fallback = true })
      picker:close()
      if #selected > 1 then
        local paths = {}
        for i, sel in ipairs(selected) do
          paths[i] = sel.file
        end
        require("images").gallery(paths)
      elseif item then
        require("images").show(item.file)
      end
    end,
    -- The overlay belongs to the terminal, not to the picker window — on close
    -- (whether by selection or Esc) it would otherwise linger until the next
    -- full repaint.
    on_close = function()
      require("images.terminal").clear()
    end,
  })
end

--- Fallback without snacks: a plain selection with no live preview, the same
--- pattern as `images.list`.
---@param root string
---@param files string[]
local function open_select(root, files)
  ---@param path string
  local function format_item(path)
    return path:sub(#root + 2)
  end

  local function on_pick(choice)
    if choice then require("images").show(choice) end
  end

  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if ok and kit.select then
    kit.select({ items = files, title = "Images: " .. root, format_item = format_item, on_select = on_pick })
    return
  end

  vim.ui.select(files, { prompt = "Show image", format_item = format_item }, on_pick)
end

--- Search for images below a scope and pick one to display.
---@param scope string|nil "cfile"|"cwd"|"path"; nil = "cwd"
---@param arg string|nil for scope="path": the target directory
---@return nil
function M.open(scope, arg)
  local root, err = M.roots(scope, arg)
  if not root then
    notify().warn(err or "no root found")
    return
  end

  local files = M.scan(root)
  if #files == 0 then
    notify().info("no images found below: " .. root)
    return
  end

  require("images.guard").check()

  if M.snacks_available() then
    open_snacks(root, files)
  else
    open_select(root, files)
  end
end

return M
