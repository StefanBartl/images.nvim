-- TESTS/sanitize_filename_spec.lua — Dateinamen-Bereinigung für `:Image paste`.
--
-- Reine Funktion, kein Terminal/Dateisystem nötig — dieselbe Trennung wie
-- `images.gallery`/`images.scale`.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local sanitize = require("images.paste").sanitize_filename

  -- ── Endung wird immer auf .png erzwungen ────────────────────────────────────
  H.eq(sanitize("screenshot"), "screenshot.png", "ohne Endung wird .png angehängt")
  H.eq(sanitize("screenshot.jpg"), "screenshot.png", "eine andere Endung wird ersetzt")
  H.eq(sanitize("screenshot.png"), "screenshot.png", "eine bereits passende Endung bleibt gleich")
  H.eq(sanitize("archiv.tar.gz"), "archiv.tar.png", "nur die letzte Endung wird ersetzt")

  -- ── Pfadanteile werden verworfen, nicht respektiert ─────────────────────────
  H.eq(sanitize("../../etc/passwd"), "passwd.png", "Verzeichnisanteile werden verworfen, kein Escape aus paste.dir")
  H.eq(sanitize("sub/dir/name"), "name.png", "auch ein normaler Unterpfad wird auf den Namen reduziert")
  H.eq(sanitize("C:\\Windows\\name"), "name.png", "Windows-Backslashes werden ebenso behandelt")

  -- ── Nichts Brauchbares übrig → nil, nicht leer ──────────────────────────────
  H.eq(sanitize(""), nil, "leere Eingabe liefert nil")
  H.eq(sanitize("   "), nil, "nur Leerraum liefert nil")
  H.eq(sanitize(".."), nil, "'..' allein liefert nil, nicht '...png'")
  H.eq(sanitize("."), nil, "'.' allein liefert nil")
  H.eq(sanitize("../.."), nil, "reine Traversal-Eingabe liefert nil")

  -- ── Leerraum um den eigentlichen Namen wird entfernt ────────────────────────
  H.eq(sanitize("  name  "), "name.png", "führender/nachgestellter Leerraum wird getrimmt")
end
