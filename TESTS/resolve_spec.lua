-- TESTS/resolve_spec.lua — Link-Erkennung und Endungsprüfung.
--
-- Vor allem die reinen Anteile: `links_in_line` und `is_image` brauchen weder
-- Dateisystem noch Buffer. `to_path`s lokale Auflösung ist hier bewusst nicht
-- abgedeckt (braucht ein echtes Dateisystem); `under_cursor`s Remote-Zweig
-- am Ende ist es, weil genau der sich mit `images.remote` geändert hat.

---@param H table Harness aus TESTS/run.lua
return function(H)
  require("images.config").setup(nil) -- Defaults, für `extensions`
  local resolve = require("images.resolve")

  -- ── is_image ───────────────────────────────────────────────────────────────
  H.ok(resolve.is_image("bild.png"), "png ist ein Bild")
  H.ok(resolve.is_image("BILD.PNG"), "Endung wird case-insensitiv geprüft")
  H.ok(resolve.is_image("a/b/c.jpeg"), "Pfad stört die Endungsprüfung nicht")
  H.falsy(resolve.is_image("notiz.md"), "md ist kein Bild")
  H.falsy(resolve.is_image("ohne-endung"), "ohne Endung kein Bild")
  H.falsy(resolve.is_image("archiv.png.gz"), "nur die letzte Endung zählt")

  -- ── links_in_line ──────────────────────────────────────────────────────────
  local links = resolve.links_in_line("kein Link hier")
  H.eq(#links, 0, "Zeile ohne Link liefert nichts")

  links = resolve.links_in_line("![alt](bild.png)")
  H.eq(#links, 1, "ein Bildlink wird erkannt")
  H.eq(links[1].target, "bild.png", "Ziel wird extrahiert")
  H.eq(links[1].from, 1, "Bereich beginnt beim `!`")
  H.eq(links[1].to, 16, "Bereich endet bei der schließenden Klammer")

  links = resolve.links_in_line("text [doc](a.md) mehr ![i](b.png) ende")
  H.eq(#links, 2, "mehrere Links in einer Zeile")
  H.eq(links[1].target, "a.md", "erstes Ziel")
  H.eq(links[2].target, "b.png", "zweites Ziel")
  H.ok(links[2].from > links[1].to, "die Bereiche überlappen nicht")

  -- Der Bereich muss den ganzen Link umfassen, nicht nur den Klammerteil —
  -- sonst greift der Hover nur, wenn der Cursor rechts vom `]` steht.
  links = resolve.links_in_line("![beschreibung](x.png)")
  local inside_alt = 5 -- irgendwo im Alt-Text
  H.ok(inside_alt >= links[1].from and inside_alt <= links[1].to, "Alt-Text zählt zum Link")

  -- Pfade mit Leerzeichen und Unterverzeichnissen.
  links = resolve.links_in_line("![](assets/mein bild.png)")
  H.eq(links[1].target, "assets/mein bild.png", "Leerzeichen im Ziel bleiben erhalten")

  -- Verschachtelte Klammern im Alt-Text dürfen die Erkennung nicht abbrechen.
  links = resolve.links_in_line("![a [b] c](d.png)")
  H.eq(#links, 1, "Klammern im Alt-Text brechen die Erkennung nicht")
  H.eq(links[1].target, "d.png", "…und das Ziel stimmt trotzdem")

  -- ── under_cursor: Remote-Link liefert die URL selbst, ohne Netzwerkzugriff ──
  -- Der einzige Teil von under_cursor, der hier abgedeckt wird (siehe Kopf-
  -- kommentar) — weil es die eine Stelle ist, an der sich das Verhalten für
  -- images.remote geändert hat: ein Remote-Ziel wird durchgereicht statt wie
  -- jeder andere unauflösbare Pfad als "nicht gefunden" verworfen.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![remote](https://example.com/foto.jpg)" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local target, err = resolve.under_cursor()
  H.ok(target ~= nil, "Remote-Link wird als Ziel erkannt: " .. tostring(err))
  H.eq(target and target.path, "https://example.com/foto.jpg", "path ist die URL selbst, nicht nil")
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end
