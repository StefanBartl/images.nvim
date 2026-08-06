# FEATURES — Ideen im Plugin selbst

Umgesetztes steht in [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt),
nicht hier — diese Liste ist bewusst nur, was noch offen ist.

## Anzeige

- **Zoom und Ausschnitt** — `+`/`-` zum Skalieren, `hjkl` zum Verschieben,
  solange ein Bild angeheftet ist. Braucht einen Modus-Zustand und ein
  Neuzeichnen pro Schritt; ohne Bild-IDs im Protokoll bedeutet jeder Schritt
  eine vollständige Neuübertragung.
- **Im Floating-Window statt über dem Text.** `:Image zen` macht das bereits
  für die Einzelanzeige (eigener Buffer, `q` schließt). Für die beiläufige
  Anzeige (`:Image show`/`hover`) bleibt es beim Draw-over-text-Modell, der
  bei Cursorbewegung verschwindet — ein zweiter Float-Modus dafür wäre die
  offene Arbeit hier, nicht das Grundprinzip.
- **Mehrere angeheftete Bilder gleichzeitig**, jedes mit eigener Position.
  Erfordert eine Platzierungsverwaltung, die es derzeit bewusst nicht gibt —
  `:Image pin` hält heute genau ein Bild fest.
- **Thumbnail-Leiste** am unteren Rand mit allen Bildern des Buffers, das
  aktive hervorgehoben — `:Image next`/`prev` würde darin wandern.
- **Animierte GIFs.** WezTerm spielt sie ab; ungeklärt ist, was beim
  Aufräumen per Repaint passiert.

## Quellen

- **Remote-Bilder** (`https://…`) über einen Download in ein Cache-Verzeichnis.
  `resolve.to_path` gibt für URLs heute bewusst `nil` zurück.
- **Bilder aus Archiven** (`.zip`, `.tar.gz`) ohne vorheriges Entpacken.
- **PDF-Seiten als Bild** — siehe `pdfport.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).

## Zwischenablage und Bearbeitung

- **Screenshot direkt auslösen** statt die Zwischenablage zu lesen
  (Windows: Snipping Tool, Linux: `grim`/`maim`, macOS: `screencapture`).
  Für Support-Dokumentation der eigentliche Alltagsfall: ein Schritt statt drei.
- **Zuschneiden und Annotieren** (Pfeile, Kästen, Unkenntlichmachung) direkt
  nach dem Einfügen. Für Screenshots aus Support-Fällen wäre das
  Unkenntlichmachen von Kundendaten der wichtigste Teil.

## Bedienung

- **Sitzungsübergreifend angeheftete Bilder**, siehe `sessions.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
