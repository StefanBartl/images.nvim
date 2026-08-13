-- TESTS/keymaps_spec.lua — which-key-Gruppierung des `<leader>i`-Präfix.
--
-- which-key selbst wird nicht gebraucht: `images.bindings.which_key` fragt
-- es nur per `pcall(require, "which-key")` ab, und `package.loaded` lässt
-- sich mit einem Fake vorbelegen. Getestet wird durch die öffentliche
-- Schnittstelle (`keymaps.register`), nicht durch eine freigelegte
-- Interna-Funktion — dasselbe Vorgehen wie in den übrigen Specs dieses Repos.

---@param H table Harness aus TESTS/run.lua
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

  -- ── Gemeinsames Präfix wird als Gruppe registriert ─────────────────────────
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
  H.eq(#fake.calls, 1, "eine which-key-Registrierung bei gemeinsamem Präfix")
  H.eq(fake.calls[1][1][1], "<leader>i", "das Präfix ist der gemeinsame Anfang")
  H.ok(fake.calls[1][1].group ~= nil, "…mit einem Gruppennamen")

  -- ── Nur eine Bindung: kein gemeinsamer Anfang, keine Gruppe ────────────────
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
  H.eq(#fake.calls, 0, "eine einzelne Bindung braucht keine Gruppenbeschriftung")

  -- ── Keine Bindungen: kein Aufruf ────────────────────────────────────────────
  reset()
  fake = install_fake_which_key()
  keymaps.register({
    ---@diagnostic disable-next-line: missing-fields
    keymaps = { show = false, gallery = false, next = false, prev = false, paste = false, filetypes = {} },
  })
  H.eq(#fake.calls, 0, "ohne Bindungen wird nichts registriert")

  -- ── Präfix, das selbst eine vollständige Bindung wäre: keine Gruppe ────────
  -- Zwei Bindungen unter derselben Taste (eine Aktion, eine Gruppe) wäre
  -- irreführend, deshalb wird das erkannt und übersprungen.
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
  H.eq(#fake.calls, 0, "ein Präfix, das selbst eine Bindung ist, wird nicht als Gruppe registriert")

  -- ── Ohne which-key: kein Fehler ─────────────────────────────────────────────
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
  H.ok(ok, "fehlendes which-key ist ein no-op, kein Fehler")

  -- ── Doppelklick überschreibt kein fremdes <2-LeftMouse> ───────────────────
  -- Andere Plugins (markdown.nvim) belegen dieselbe Taste auf denselben
  -- Filetypes und routen dort mehr als nur Bildlinks; images.nvim tritt dann
  -- zurück, statt die Ladereihenfolge entscheiden zu lassen.
  reset()

  ---@param ft string
  ---@param pre_mapped boolean ein fremdes <2-LeftMouse> vorher setzen
  ---@return string|nil desc der am Ende gültigen Bindung
  local function double_click_desc(ft, pre_mapped)
    local buf = vim.api.nvim_create_buf(false, true)
    if pre_mapped then vim.keymap.set("n", "<2-LeftMouse>", function() end, { buffer = buf, desc = "fremd" }) end
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
    "images: Bild bei Doppelklick auf Link",
    "ohne Vorbelegung setzt images.nvim seinen Doppelklick"
  )
  H.eq(double_click_desc("images_ft_taken", true), "fremd", "eine vorhandene Bindung bleibt unangetastet")

  reset()
end
