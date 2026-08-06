-- TESTS/remote_spec.lua — Remote-Bild-Erkennung und der Default-Aus-Zustand.
--
-- Kein echter Download in diesem Test: `fetch` mit dem Default
-- (`display.remote.enabled = false`) liefert seinen Fehler synchron, ohne
-- jemals ein Netzwerk anzufassen — genau der Fall, der ohne Zustimmung
-- niemals eine Anfrage auslösen soll.

---@param H table Harness aus TESTS/run.lua
return function(H)
  local remote = require("images.remote")

  -- ── is_remote: nur http(s) ──────────────────────────────────────────────────
  H.ok(remote.is_remote("https://example.com/bild.png"), "https wird erkannt")
  H.ok(remote.is_remote("http://example.com/bild.png"), "http wird erkannt")
  H.falsy(remote.is_remote("ftp://example.com/bild.png"), "ftp wird bewusst nicht unterstützt")
  H.falsy(remote.is_remote("/lokal/bild.png"), "ein lokaler Pfad ist nicht remote")
  H.falsy(remote.is_remote("C:\\lokal\\bild.png"), "ein Windows-Pfad ist nicht remote")
  H.falsy(remote.is_remote("relativ/bild.png"), "ein relativer Pfad ist nicht remote")

  -- ── fetch: default aus, kein Netzwerkzugriff ────────────────────────────────
  require("images.config").setup(nil) -- Defaults: remote.enabled = false
  local png, err = remote.fetch("https://example.com/bild.png")
  H.falsy(png, "ohne Zustimmung wird nichts geladen")
  H.contains(err or "", "deaktiviert", "…mit einer Begründung, die auf die Option verweist")
  H.contains(err or "", "display.remote.enabled", "…und zwar der genaue Optionsname")

  -- ── resolve.is_image erkennt Remote-URLs mit erkennbarer Endung ─────────────
  local resolve = require("images.resolve")
  H.ok(resolve.is_image("https://example.com/foto.jpg"), "https-URL mit Endung gilt als Bild")
  H.ok(resolve.is_image("https://example.com/foto.png?v=2"), "…auch mit Query-String danach")
  H.falsy(resolve.is_image("https://example.com/api/image"), "…aber nicht ohne erkennbare Endung")

  -- ── resolve.to_path lädt Remote-URLs nicht (bleibt Sache von images.remote) ─
  H.eq(
    resolve.to_path("https://example.com/foto.jpg"),
    nil,
    "to_path bleibt rein lokal, auch mit aktivem remote wäre das falsch hier"
  )
end
