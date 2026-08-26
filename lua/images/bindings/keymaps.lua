---@module 'images.bindings.keymaps'
---@brief Keymaps for images.nvim — all optional, all which-key aware.
---@description
--- Every binding is buffer-local and tied to the filetypes from
--- `keymaps.filetypes`. Each one can be disabled with `false` or moved to a
--- different key; an empty `keymaps` block registers nothing at all.

local M = {}

local DOUBLE_CLICK = "<2-LeftMouse>"

--- Binding -> action. A table rather than five `if` blocks, so a new binding
--- only needs an entry here.
---@type { option: string, desc: string, run: fun() }[]
local ACTIONS = {
  {
    option = "show",
    desc = "images: show the image under the cursor",
    run = function()
      require("images").hover()
    end,
  },
  {
    option = "gallery",
    desc = "images: every image in the buffer, side by side",
    run = function()
      require("images").gallery()
    end,
  },
  {
    option = "next",
    desc = "images: next image",
    -- `step` already wraps modulo the image count, so multiplying the delta
    -- is all a count needs: `3<leader>in` lands three images on, wrapping
    -- exactly as one step would.
    run = function()
      require("images").step(vim.v.count1)
    end,
  },
  {
    option = "prev",
    desc = "images: previous image",
    run = function()
      require("images").step(-vim.v.count1)
    end,
  },
  {
    option = "paste",
    desc = "images: paste an image from the clipboard",
    -- A count asks for the name: `M.paste(name)` has always accepted one, but
    -- a bare lhs carries no text, so `:Image paste {name}` was the only way
    -- in. `1<leader>ip` prompts; without a count nothing changes.
    run = function()
      require("images").paste(nil, vim.v.count ~= 0)
    end,
  },
  {
    option = "screenshot",
    desc = "images: take a screenshot and insert it",
    run = function()
      require("images").screenshot(vim.v.count ~= 0)
    end,
  },
}

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
  for _, action in ipairs(ACTIONS) do
    local lhs = keys[action.option]
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

--- Register the keymaps.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  local keys = cfg.keymaps or {}

  local prefix = common_prefix(keys)
  if prefix then require("images.bindings.which_key").setup(prefix) end

  local map = require("lib.nvim.bindings.keymap")
  ---@param ev { buf: integer }
  require("lib.nvim.bindings.autocmd").create("FileType", function(ev)
    if not vim.api.nvim_buf_is_valid(ev.buf) then return end
    for _, action in ipairs(ACTIONS) do
      local lhs = keys[action.option]
      if type(lhs) == "string" and lhs ~= "" then map("n", lhs, action.run, { buffer = ev.buf }, action.desc) end
    end
    if keys.double_click then map_double_click(ev.buf) end
  end, {
    group = require("lib.nvim.bindings.autocmd").group("images.keymaps", true),
    pattern = keys.filetypes or { "markdown" },
    desc = "images: install the buffer-local keymaps",
  })
end

return M
