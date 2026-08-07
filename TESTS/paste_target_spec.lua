-- TESTS/paste_target_spec.lua — Zielverzeichnis-Logik von `:Image paste`.
--
-- Deckt drei echte Fixes ab, alle ohne echte Zwischenablage: `paste_with_name`
-- und `capture_with_optional_name` nehmen `capture` als Parameter entgegen,
-- ein Fake genügt also (derselbe Trick wie orphans_spec.lua für Dateisystem-
-- Tests ohne Terminal).
--
--   1. Schlägt `capture` fehl (kein Bild in der Zwischenablage), wird KEIN
--      Zielverzeichnis angelegt — vorher legte `target_paths` das Verzeichnis
--      an, bevor überhaupt feststand, ob es etwas hineinzuschreiben gibt.
--   2. Existiert im Dokumentverzeichnis bereits "Resources" oder "Ressourcen",
--      wird dieses statt `paste.dir` ("assets") verwendet, kein zweites
--      Verzeichnis entsteht.
--   3. `:Image paste {name}` (direct_name) überspringt jede Namensabfrage und
--      verwendet den angegebenen Namen direkt.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local paste = require("images.paste")
  require("images.config").setup(nil) -- Default paste.dir = "assets"

  ---@param root string
  ---@return integer buf
  local function make_buf(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    return buf
  end

  ---@param ok boolean
  ---@return fun(out: string, cb: fun(ok: boolean, err: string|nil))
  local function fake_capture(ok)
    return function(out, cb)
      if ok then
        local fd = assert(io.open(out, "wb"))
        fd:write("x")
        fd:close()
        cb(true)
      else
        cb(false, "Kein Bild in der Zwischenablage")
      end
    end
  end

  -- ── 1. Fehlgeschlagene Aufnahme legt kein Zielverzeichnis an ──────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, nil, fake_capture(false))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "kein Bild in der Zwischenablage -> kein assets-Ordner")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 1b. Erfolgreiche Aufnahme legt das Verzeichnis an und schreibt hinein ──
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 1, "erfolgreiche Aufnahme legt assets an")
    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "…und die Datei landet darin")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.ok(lines[1]:find("assets/shot.png", 1, true) ~= nil, "Link wird eingefügt: " .. lines[1])
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 2. Ein vorhandener "Resources"-Ordner wird verwendet statt "assets" ────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.mkdir(root .. "/Resources", "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "kein zusätzlicher assets-Ordner")
    H.eq(vim.fn.filereadable(root .. "/Resources/shot.png"), 1, "Datei landet im vorhandenen Resources-Ordner")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 2b. "Ressourcen" (deutsch) wird ebenso erkannt, case-insensitiv ────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.mkdir(root .. "/ressourcen", "p") -- Kleinschreibung
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "kein zusätzlicher assets-Ordner")
    H.eq(
      vim.fn.filereadable(root .. "/ressourcen/shot.png"),
      1,
      "Datei landet im vorhandenen ressourcen-Ordner (case-insensitiv erkannt)"
    )
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 3. direct_name überspringt jede Abfrage und wird direkt verwendet ──────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)
    vim.api.nvim_set_current_buf(buf)

    paste.capture_with_optional_name(fake_capture(true), "mein Bild")

    H.eq(vim.fn.filereadable(root .. "/assets/mein Bild.png"), 1, "direct_name wird sanitisiert direkt verwendet, ohne Abfrage")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 3b. Ein direct_name, der nach dem Sanitizing leer ist, bricht ab ───────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)
    vim.api.nvim_set_current_buf(buf)

    local ok = pcall(paste.capture_with_optional_name, fake_capture(true), "..")
    H.ok(ok, "ungültiger direct_name wirft nicht, sondern meldet nur einen Fehler")
    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "…und legt kein Verzeichnis an")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end
