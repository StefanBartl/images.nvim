# FEATURES — Ideen im Plugin selbst

Umgesetztes steht in [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt),
nicht hier — diese Liste ist bewusst nur, was noch offen ist.

## Anzeige

- **Thumbnail-Leiste** am unteren Rand mit allen Bildern des Buffers, das
  aktive hervorgehoben — `:Image next`/`prev` würde darin wandern.
- **Animierte GIFs.** WezTerm spielt sie ab; ungeklärt ist, was beim
  Aufräumen per Repaint passiert.

## Quellen

- **Remote-Bilder für gallery/compare/pickers/zen.** `:Image show` und Hover
  können seit [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt)
  http(s)-Bilder laden; die Scan-basierten Commands lösen einen Remote-Link
  aber weiterhin nicht auf — bewusst, damit ein bloßes Auflisten der Bilder
  eines Buffers nicht N Netzwerkanfragen auslöst (siehe `images.remote`s
  Moduldoc). Diese vier Commands bewusst mit einzuschließen wäre die
  offene Arbeit, nicht das Herunterladen selbst.
- **PDF-Seiten als Bild** — siehe `pdfport.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).

## Zwischenablage und Bearbeitung

- **Zuschneiden und Annotieren** (Pfeile, Kästen, Unkenntlichmachung) direkt
  nach dem Einfügen. Für Screenshots aus Support-Fällen wäre das
  Unkenntlichmachen von Kundendaten der wichtigste Teil.

## Bedienung

- **Sitzungsübergreifend angeheftete Bilder**, siehe `sessions.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
