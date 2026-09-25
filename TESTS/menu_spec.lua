-- TESTS/menu_spec.lua — images.integrations.menu: the nvzone/menu-shaped
-- entry list a host splices into its own right-click menu.
--
-- `images.integrations.menu` hard-requires `ui.contextmenu` at module load
-- (unlike every soft integration in `images.init`, which `pcall`s `ui.kit` —
-- see images/init.lua's own `kit()`): a host only ever loads this module
-- because it is already building a menu with ui.nvim's builders, so that is
-- a deliberate hard dependency, not a bug (see docs/CONTRIBUTING.md: this is
-- one of the "soft-dependency bridges" under `integrations/`, soft meaning
-- the *target* — nvzone/menu — not ui.nvim itself).
--
-- TESTS/run.lua deliberately does NOT add ui.nvim to this suite's shared
-- runtimepath/package.path — compare_spec.lua's regression coverage for
-- `:Image compare` depends on `ui.kit` staying unreachable there (see its own
-- header). So this spec resolves ui.nvim on its own, scoped to this file: it
-- extends `package.path` only for the duration of this function and restores
-- the original value before returning, on every exit path, so no other spec
-- (run before or after this one) ever observes the change. If no sibling
-- checkout is found, this spec is a clean no-op, the same convention
-- resolve_spec.lua uses for its own gopath.nvim block.

---@param H table harness from TESTS/run.lua
return function(H)
  local repo = vim.fs.normalize(vim.uv.cwd())

  ---@return string|nil
  local function find_ui_nvim()
    local candidates = {}
    if vim.env.UI_NVIM_PATH then candidates[#candidates + 1] = vim.env.UI_NVIM_PATH end
    candidates[#candidates + 1] = repo .. "/../ui.nvim"
    candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/ui.nvim"
    for _, path in ipairs(candidates) do
      local norm = vim.fs.normalize(path)
      if vim.fn.isdirectory(norm .. "/lua/ui") == 1 then return norm end
    end
    return nil
  end

  local ui_nvim = find_ui_nvim()
  if not ui_nvim then return end -- no sibling checkout: nothing to test against

  local original_package_path = package.path
  package.path = table.concat({ ui_nvim .. "/lua/?.lua", ui_nvim .. "/lua/?/init.lua", package.path }, ";")

  local ok_menu, menu = pcall(require, "images.integrations.menu")
  if not ok_menu then
    -- A sibling checkout exists but does not actually provide ui.contextmenu
    -- (an unrelated or half-built directory) — degrade the same as "absent".
    package.path = original_package_path
    return
  end

  require("images.config").setup(nil)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"

  -- ── enabled, allowed filetype: a populated, well-shaped list ─────────────
  local items = menu.items(buf)
  H.ok(#items > 0, "a markdown buffer with menu.enable = true gets entries")
  for i, item in ipairs(items) do
    H.ok(type(item.name) == "string" and #item.name > 0, ("item %d has a non-empty name"):format(i))
  end

  -- ── menu.enable = false: no entries, regardless of filetype ──────────────
  require("images.config").setup({ menu = { enable = false } })
  H.eq(#menu.items(buf), 0, "menu.enable = false returns no entries")

  -- ── enabled(): what ui.nvim's ui.menu asks first ─────────────────────────
  require("images.config").setup({})
  H.eq(menu.enabled(), true, "enabled() is true by default")
  require("images.config").setup({ integrations = { ui_menu = false } })
  H.eq(menu.enabled(), false, "integrations.ui_menu = false -> enabled() false")
  H.ok(#menu.items(buf) > 0, "ui_menu = false leaves items() to other hosts")
  require("images.config").setup({ menu = { enable = false } })
  H.eq(menu.enabled(), false, "menu.enable = false -> enabled() false")

  -- ── filetype not in keymaps.filetypes: no entries ─────────────────────────
  require("images.config").setup({})
  vim.bo[buf].filetype = "lua"
  H.eq(#menu.items(buf), 0, "an unconfigured filetype returns no entries")

  -- ── no filetype at all: no entries (not an error) ─────────────────────────
  vim.bo[buf].filetype = ""
  H.eq(#menu.items(buf), 0, "a buffer with no filetype returns no entries")

  -- ── submenu(): nil when there is nothing to show, an item when there is ──
  vim.bo[buf].filetype = "markdown"
  require("images.config").setup({})
  H.ok(menu.submenu(nil, buf) ~= nil, "submenu() wraps a non-empty item list")
  require("images.config").setup({ menu = { enable = false } })
  H.eq(menu.submenu(nil, buf), nil, "submenu() is nil when items() is empty")

  require("images.config").setup({})
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  package.path = original_package_path
end
