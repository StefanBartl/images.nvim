-- TESTS/orphans_spec.lua — verwaiste Bilder im Zielverzeichnis finden.
--
-- Braucht echtes Dateisystem und einen benannten Buffer (target_dir hängt an
-- `nvim_buf_get_name`), ist also kein reines Modul wie gallery/resolve/info —
-- aber immer noch ohne Terminal prüfbar, was hier gezeigt wird.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local orphans = require("images.orphans")
  require("images.config").setup(nil) -- Default paste.dir = "assets"

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(root .. "/assets", "p")

  ---@param path string
  local function touch(path)
    local fd = assert(io.open(path, "wb"))
    fd:write("x")
    fd:close()
  end

  touch(root .. "/assets/a.png")
  touch(root .. "/assets/b.png")
  touch(root .. "/assets/notes.txt") -- keine Bilddatei, muss ignoriert werden

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![a](assets/a.png)" })
  -- Buffer-Namen sind erst nach dem ersten Schreiben/:write real auf der
  -- Platte verankert; `resolve.to_path` prüft aber nur `fs_stat` auf den
  -- berechneten Pfad, der schon aus dem (noch ungespeicherten) Namen folgt.

  -- ── a.png ist referenziert, b.png nicht ────────────────────────────────────
  local found = orphans.find(buf)
  H.eq(#found, 1, "genau ein Bild ist verwaist")
  H.eq(found[1].rel, "b.png", "…nämlich das unreferenzierte")

  -- ── Nach dem Verlinken ist nichts mehr verwaist ────────────────────────────
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "![b](assets/b.png)" })
  found = orphans.find(buf)
  H.eq(#found, 0, "beide referenziert → keine Verwaisten mehr")

  -- ── Kein Zielverzeichnis: kein Fehler, leere Liste ─────────────────────────
  local other_root = vim.fn.tempname()
  vim.fn.mkdir(other_root, "p")
  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(other_buf, other_root .. "/doc.md")
  found = orphans.find(other_buf)
  H.eq(#found, 0, "fehlendes Zielverzeichnis liefert eine leere Liste, keinen Fehler")

  -- ── Nicht-Bilddateien werden nicht mitgezählt ──────────────────────────────
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  found = orphans.find(buf)
  local rels = {}
  for _, o in ipairs(found) do
    rels[o.rel] = true
  end
  H.falsy(rels["notes.txt"], "notes.txt ist kein Bild und taucht nicht auf")
  H.ok(rels["a.png"] and rels["b.png"], "beide Bilder sind jetzt unreferenziert")

  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  pcall(vim.api.nvim_buf_delete, other_buf, { force = true })
end
