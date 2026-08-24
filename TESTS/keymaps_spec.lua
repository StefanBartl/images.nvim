-- TESTS/keymaps_spec.lua — which-key grouping of the `<leader>i` prefix.
--
-- which-key itself is not needed: `images.bindings.which_key` only asks for it
-- via `pcall(require, "which-key")`, and `package.loaded` can be primed with a
-- fake. Tested through the public interface (`keymaps.register`) rather than an
-- exposed internal — the same approach as the rest of this repo's specs.

---@param H table harness from TESTS/run.lua
return function(H)
  local keymaps = require("images.bindings.keymaps")

  ---@return { calls: table[] }
  local function install_fake_which_key()
    local fake = { calls = {} }
    package.loaded["which-key"] = {
      add = function(specs)
        table.insert(fake.calls, specs)
      end,
    }
    return fake
  end

  local function reset()
    package.loaded["which-key"] = nil
    package.loaded["images.bindings.which_key"] = nil
  end

  -- ── A common prefix is registered as a group ─────────────────────────────
  reset()
  local fake = install_fake_which_key()
  keymaps.register({
    ---@diagnostic disable-next-line: missing-fields
    keymaps = {
      show = "<leader>im",
      gallery = "<leader>ig",
      next = "<leader>in",
      prev = "<leader>ip",
      paste = "<leader>iv",
      double_click = false,
      filetypes = {},
    },
  })
  H.eq(#fake.calls, 1, "one which-key registration for a shared prefix")
  H.eq(fake.calls[1][1][1], "<leader>i", "the prefix is the shared beginning")
  H.ok(fake.calls[1][1].group ~= nil, "…with a group name")

  -- ── One binding only: no shared beginning, no group ──────────────────────
  reset()
  fake = install_fake_which_key()
  keymaps.register({
    ---@diagnostic disable-next-line: missing-fields
    keymaps = {
      show = "<leader>im",
      gallery = false,
      next = false,
      prev = false,
      paste = false,
      double_click = false,
      filetypes = {},
    },
  })
  H.eq(#fake.calls, 0, "a single binding needs no group label")

  -- ── No bindings: no call ─────────────────────────────────────────────────
  reset()
  fake = install_fake_which_key()
  keymaps.register({
    ---@diagnostic disable-next-line: missing-fields
    keymaps = { show = false, gallery = false, next = false, prev = false, paste = false, filetypes = {} },
  })
  H.eq(#fake.calls, 0, "with no bindings nothing is registered")

  -- ── A prefix that is itself a complete binding: no group ─────────────────
  -- Two bindings under the same key (one action, one group) would be
  -- misleading, so this is detected and skipped.
  reset()
  fake = install_fake_which_key()
  keymaps.register({
    ---@diagnostic disable-next-line: missing-fields
    keymaps = {
      show = "<leader>i",
      gallery = "<leader>ig",
      next = false,
      prev = false,
      paste = false,
      double_click = false,
      filetypes = {},
    },
  })
  H.eq(#fake.calls, 0, "a prefix that is itself a binding is not registered as a group")

  -- ── Without which-key: no error ──────────────────────────────────────────
  package.loaded["which-key"] = nil
  package.loaded["images.bindings.which_key"] = nil
  local ok = pcall(keymaps.register, {
    keymaps = {
      show = "<leader>im",
      gallery = "<leader>ig",
      next = false,
      prev = false,
      paste = false,
      double_click = false,
      filetypes = {},
    },
  })
  H.ok(ok, "a missing which-key is a no-op, not an error")

  -- ── The double click does not overwrite a foreign <2-LeftMouse> ──────────
  -- Other plugins (markdown.nvim) claim the same key on the same filetypes and
  -- route more than just image links there; images.nvim yields rather than
  -- letting load order decide.
  reset()

  ---@param ft string
  ---@param pre_mapped boolean install a foreign <2-LeftMouse> beforehand
  ---@return string|nil desc of the binding that ends up in effect
  local function double_click_desc(ft, pre_mapped)
    local buf = vim.api.nvim_create_buf(false, true)
    if pre_mapped then vim.keymap.set("n", "<2-LeftMouse>", function() end, { buffer = buf, desc = "foreign" }) end
    keymaps.register({
      ---@diagnostic disable-next-line: missing-fields
      keymaps = {
        show = false,
        gallery = false,
        next = false,
        prev = false,
        paste = false,
        double_click = true,
        filetypes = { ft },
      },
    })
    vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

    local want = vim.api.nvim_replace_termcodes("<2-LeftMouse>", true, true, true)
    local found
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if vim.api.nvim_replace_termcodes(m.lhs or "", true, true, true) == want then found = m.desc end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    return found
  end

  H.eq(
    double_click_desc("images_ft_free", false),
    "images: show image on double-clicking a link",
    "with nothing pre-installed, images.nvim sets its double click"
  )
  H.eq(double_click_desc("images_ft_taken", true), "foreign", "an existing binding stays untouched")

  reset()
end
