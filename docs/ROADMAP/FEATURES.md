# FEATURES — Ideen im Plugin selbst

## Anzeige

- **Vergleichsmodus** `:Image compare a.png b.png` — zwei Bilder nebeneinander
  mit gemeinsamer Skalierung, damit Größenunterschiede sichtbar bleiben statt
  wegnormiert zu werden. Die Galerie skaliert heute jede Kachel für sich.
- **Zoom und Ausschnitt** — `+`/`-` zum Skalieren, `hjkl` zum Verschieben,
  solange ein Bild angeheftet ist. Braucht einen Modus-Zustand und ein
  Neuzeichnen pro Schritt; ohne Bild-IDs im Protokoll bedeutet jeder Schritt
  eine vollständige Neuübertragung.
- **Im Floating-Window statt über dem Text.** Heute liegt das Bild auf dem
  Schirm und verschwindet bei der nächsten Cursorbewegung. Ein Float mit
  eigenem Buffer würde Scrollen, Fokus und `q` zum Schließen erlauben — die
  Positionsberechnung müsste dann dem Fenster folgen statt dem Cursor.
- **Mehrere angeheftete Bilder gleichzeitig**, jedes mit eigener Position.
  Erfordert eine Platzierungsverwaltung, die es derzeit bewusst nicht gibt.
- **Thumbnail-Leiste** am unteren Rand mit allen Bildern des Buffers, das
  aktive hervorgehoben — `:Image next`/`prev` würde darin wandern.
- **Animierte GIFs.** WezTerm spielt sie ab; ungeklärt ist, was beim
  Aufräumen per Repaint passiert.

## Quellen

- **Remote-Bilder** (`https://…`) über einen Download in ein Cache-Verzeichnis.
  `resolve.to_path` gibt für URLs heute bewusst `nil` zurück.
- **Bilder aus Archiven** (`.zip`, `.tar.gz`) ohne vorheriges Entpacken.
- **SVG** — WezTerm kann es nicht, ImageMagick schon. Wäre der erste Fall, in
  dem eine Konvertierung wirklich nötig ist; laut Leitplanke dann als
  *Verbesserung* mit klarer Meldung, wenn `magick` fehlt.
- **PDF-Seiten als Bild** — siehe `pdfport.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).

## Zwischenablage und Bearbeitung

- **Screenshot direkt auslösen** statt die Zwischenablage zu lesen
  (Windows: Snipping Tool, Linux: `grim`/`maim`, macOS: `screencapture`).
  Für Support-Dokumentation der eigentliche Alltagsfall: ein Schritt statt drei.
- **Dateinamen erfragen** statt des Zeitstempel-Templates, mit dem Template
  als Vorbelegung.
- **Alt-Text abfragen**, damit aus `![](…)` ein `![Beschreibung](…)` wird —
  für die Barrierefreiheit der erzeugten Dokumentation relevant.
- **Bild ersetzen**: Cursor auf einem bestehenden Link, `:Image replace`
  überschreibt die Zieldatei mit dem Zwischenablage-Inhalt.
- **Verwaiste Bilder finden** — Dateien im `assets`-Verzeichnis, auf die kein
  Link mehr zeigt. Das Gegenstück zu den unauflösbaren Links, die `scan`
  bereits meldet.
- **Zuschneiden und Annotieren** (Pfeile, Kästen, Unkenntlichmachung) direkt
  nach dem Einfügen. Für Screenshots aus Support-Fällen wäre das
  Unkenntlichmachen von Kundendaten der wichtigste Teil.

## Bedienung

- **`:Image` mit Range über einem Bereich** zeigt die Bilder dieses Bereichs
  als Galerie, statt nur `list` zu filtern.
- **which-key-Gruppe** für den `<leader>i`-Präfix mit sprechenden Labels.
- **Statusline-Indikator**, solange ein Bild angeheftet ist — sonst ist nicht
  erkennbar, warum das Bild nicht verschwindet.
- **Sitzungsübergreifend angeheftete Bilder**, siehe `sessions.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
