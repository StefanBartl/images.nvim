-- TESTS/browse_spec.lua — Bildscan im Dateisystem und Scope-Auflösung.
--
-- `M.walk` ist eine reine Funktion (echtes Dateisystem, aber kein Terminal),
-- genau wie `orphans.find` — geprüft wird also ohne Zeichnen. `open()` selbst
-- (das snacks.picker öffnet oder darauf zurückfällt) bleibt ungeprüft, wie
-- jeder Zeichenpfad in dieser Suite.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local browse = require("images.browse")
  require("images.config").setup(nil)

  -- ── walk: findet Bilder, überspringt konfigurierte und feste Ausschlüsse ──
  H.tmpdir(function(root)
    H.write(root .. "/a.png", "x")
    H.write(root .. "/notes.txt", "x") -- keine Bilddatei
    H.write(root .. "/sub/b.jpg", "x")
    H.write(root .. "/.git/c.png", "x") -- immer ausgeschlossen
    H.write(root .. "/node_modules/d.png", "x") -- Default-Ausschluss

    local found = browse.walk(root, { "node_modules" }, { "png", "jpg" })
    table.sort(found)
    H.eq(#found, 2, "genau zwei Bilder gefunden")
    H.contains(found[1], "a.png", "a.png ist dabei")
    H.contains(found[2], "b.jpg", "b.jpg im Unterverzeichnis ist dabei")

    for _, p in ipairs(found) do
      H.falsy(p:find(".git", 1, true), ".git bleibt immer ausgeschlossen")
      H.falsy(p:find("node_modules", 1, true), "node_modules bleibt ausgeschlossen")
    end
  end)

  -- ── walk: Endungsfilter ist case-insensitiv ────────────────────────────────
  H.tmpdir(function(root)
    H.write(root .. "/upper.PNG", "x")
    local found = browse.walk(root, {}, { "png" })
    H.eq(#found, 1, "Endung wird case-insensitiv verglichen")
  end)

  -- ── roots: cwd ──────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local chdir = require("lib.nvim.fs.chdir")
    local before = vim.uv.cwd()
    chdir(root)
    local resolved = browse.roots("cwd", nil)
    chdir(before)
    H.eq(resolved, require("images.resolve").normalize_path(root), "cwd löst auf das aktuelle Arbeitsverzeichnis auf")
  end)

  -- ── roots: nil-Scope fällt auf cwd zurück ──────────────────────────────────
  H.eq(browse.roots(nil, nil), browse.roots("cwd", nil), "kein Scope entspricht cwd")

  -- ── roots: path ─────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local resolved, err = browse.roots("path", root)
    H.eq(err, nil, "kein Fehler bei existierendem Verzeichnis")
    H.eq(resolved, require("images.resolve").normalize_path(root), "path löst auf den angegebenen Ordner auf")
  end)

  local _, err = browse.roots("path", nil)
  H.contains(err or "", "path", "path ohne Verzeichnis liefert eine verständliche Fehlermeldung")

  _, err = browse.roots("path", "/definitiv/kein/verzeichnis/hier")
  H.ok(err ~= nil, "nicht existierendes Verzeichnis liefert einen Fehler")

  -- ── roots: cfile ────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_set_current_buf(buf)
    local resolved = browse.roots("cfile", nil)
    H.eq(resolved, require("images.resolve").normalize_path(root), "cfile löst auf das Verzeichnis der Datei auf")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  -- ── roots: unbekannter Scope ────────────────────────────────────────────────
  local _, unknown_err = browse.roots("nonsense", nil)
  H.ok(unknown_err ~= nil, "unbekannter Scope liefert einen Fehler")

  -- ── snacks_available: liefert ein Boolean, ohne zu zeichnen ────────────────
  H.ok(type(browse.snacks_available()) == "boolean", "snacks_available ist ein Boolean")
end
