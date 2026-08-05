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

  reset()
end
