---@module 'images.bindings.keymaps'
---@brief Keymaps for images.nvim — all optional, all which-key aware.
---@description
--- Every binding is buffer-local and tied to the filetypes from
--- `keymaps.filetypes`. Each one can be disabled with `false` or moved to a
--- different key; an empty `keymaps` block registers nothing at all.

local M = {}

local DOUBLE_CLICK = "<2-LeftMouse>"

--- The preset's actions, by name. A table rather than six `if` blocks, so a
--- new binding only needs an entry here.
---@type table<string, Lib.Keymap.Action>
local ACTIONS = {
  show = {
    desc = "show the image under the cursor",
    rhs = function()
      require("images").hover()
    end,
  },
  gallery = {
    desc = "every image in the buffer, side by side",
    rhs = function()
      require("images").gallery()
    end,
  },
  next = {
    desc = "next image",
    -- `step` already wraps modulo the image count, so multiplying the delta
    -- is all a count needs: `3<leader>in` lands three images on, wrapping
    -- exactly as one step would.
    rhs = function()
      require("images").step(vim.v.count1)
    end,
  },
  prev = {
    desc = "previous image",
    rhs = function()
      require("images").step(-vim.v.count1)
    end,
  },
  paste = {
    desc = "paste an image from the clipboard",
    -- A count asks for the name: `M.paste(name)` has always accepted one, but
    -- a bare lhs carries no text, so `:Image paste {name}` was the only way
    -- in. `1<leader>ip` prompts; without a count nothing changes.
    rhs = function()
      require("images").paste(nil, vim.v.count ~= 0)
    end,
  },
  screenshot = {
    desc = "take a screenshot and insert it",
    rhs = function()
      require("images").screenshot(vim.v.count ~= 0)
    end,
  },
}

--- Declaration order, so docs and the health report read the same every run.
---@type string[]
local ORDER = { "show", "gallery", "next", "prev", "paste", "screenshot" }

--- Double-clicking a markdown link shows the image.
--- `<2-LeftMouse>` fires after the ordinary click, so the cursor is already
--- inside the link — which is why `hover()` suffices without evaluating the
--- position itself.
---
--- An existing buffer-local `<2-LeftMouse>` is not overwritten. Other plugins
--- claim the same key on the same filetypes (markdown.nvim, for instance, with
--- a handler routing anchor -> image -> URL -> file, which delegates here for
--- the image case anyway). Since both sides register from a `FileType`
--- autocmd, load order alone would otherwise decide the winner — and if
--- images.nvim won, a more comprehensive handler would be reduced to image
--- links only. Yielding is the right direction: a foreign handler covers the
--- image case too, but not the other way round.
---@param buf integer
---@return nil
local function map_double_click(buf)
  -- Not `maparg()`: that always queries the *current* buffer, which need not be
  -- `buf` inside a FileType callback. Termcodes on both sides, because
  -- depending on the registering plugin `lhs` comes back either as
  -- "<2-LeftMouse>" or already as a raw key sequence.
  local want = vim.api.nvim_replace_termcodes(DOUBLE_CLICK, true, true, true)
  for _, existing in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.api.nvim_replace_termcodes(existing.lhs or "", true, true, true) == want then return end
  end

  require("lib.nvim.bindings.keymap")("n", DOUBLE_CLICK, function()
    if not require("images").hover() then
      -- No image link hit: the double click should behave normally (select the
      -- word) rather than being swallowed silently.
      vim.cmd("normal! viw")
    end
  end, { buffer = buf }, "images: show image on double-clicking a link")
end

--- The longest common prefix of the configured bindings, e.g. "<leader>i" for
--- "<leader>im"/"<leader>ig"/…. Without at least two bindings sharing a start,
--- a group label is pointless.
---@param keys ImagesNvim.KeymapConfig
---@return string|nil
local function common_prefix(keys)
  local lhs_list = {}
  for _, name in ipairs(ORDER) do
    local lhs = keys[name]
    if type(lhs) == "string" and lhs ~= "" then lhs_list[#lhs_list + 1] = lhs end
  end
  if #lhs_list < 2 then return nil end

  local prefix = lhs_list[1]
  for i = 2, #lhs_list do
    local other = lhs_list[i]
    local n = math.min(#prefix, #other)
    while n > 0 and prefix:sub(1, n) ~= other:sub(1, n) do
      n = n - 1
    end
    prefix = prefix:sub(1, n)
    if prefix == "" then return nil end
  end
  -- A prefix that is already a complete binding would be misleading as a group
  -- name -- which-key would then show both an action and a group under the same
  -- key.
  for _, lhs in ipairs(lhs_list) do
    if lhs == prefix then return nil end
  end
  return prefix
end

--- Declare and bind the keymaps.
---
--- Every binding is buffer-local and tied to the filetypes from
--- `keymaps.filetypes`, so the preset is registered once per matching buffer.
--- The action set is identical in each; only the target differs, which is why
--- the registry keeps one record for the plugin rather than one per buffer.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  local keys = cfg.keymaps or {}

  ---@type Lib.Keymap.Spec
  local spec = {
    -- No fixed prefix: the bindings are all user-set, so the group -- if there
    -- is one at all -- is whatever they happen to share.
    prefix = common_prefix(keys),
    which_key = { group = "images" },
    order = ORDER,
    actions = ACTIONS,
  }

  -- `filetypes` and `double_click` live in the same block but are not actions:
  -- one says *where* the preset applies, the other is bound separately because
  -- it yields to a foreign handler. Filtering them out is what keeps the
  -- registry from reporting them as unknown action names.
  local user = vim.deepcopy(keys)
  user.filetypes = nil
  user.double_click = nil

  local keymap = require("lib.nvim.bindings.keymap")
  local autocmd = require("lib.nvim.bindings.autocmd")

  -- Declared once, here: the which-key group label is global and belongs up
  -- as soon as the preset exists, not on whichever buffer happens to match
  -- first -- and `:checkhealth` should be able to see the actions even in a
  -- session that never opens a markdown file. Nothing is bound by this call.
  keymap.register("images", spec, user, { bind = false })

  ---@param ev { buf: integer }
  autocmd.create("FileType", function(ev)
    if not vim.api.nvim_buf_is_valid(ev.buf) then return end
    keymap.register("images", spec, user, { buffer = ev.buf })
    if keys.double_click then map_double_click(ev.buf) end
  end, {
    group = autocmd.group("images.keymaps", true),
    pattern = keys.filetypes or { "markdown" },
    desc = "images: install the buffer-local keymaps",
  })
end

return M
