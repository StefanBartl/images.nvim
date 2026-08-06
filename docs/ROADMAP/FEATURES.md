# FEATURES — Ideen im Plugin selbst

Umgesetztes steht in [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt),
nicht hier — diese Liste ist bewusst nur, was noch offen ist.

## Quellen

- **Remote-Bilder für gallery/compare/pickers/zen.** `:Image show` und Hover
  können seit [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt)
  http(s)-Bilder laden; die Scan-basierten Commands lösen einen Remote-Link
  aber weiterhin nicht auf — bewusst, damit ein bloßes Auflisten der Bilder
  eines Buffers nicht N Netzwerkanfragen auslöst (siehe `images.remote`s
  Moduldoc). Diese vier Commands bewusst mit einzuschließen wäre die
  offene Arbeit, nicht das Herunterladen selbst.

## Bedienung

- **Sitzungsübergreifend angeheftete Bilder**, siehe `sessions.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
