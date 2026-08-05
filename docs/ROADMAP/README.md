# ROADMAP — images.nvim

Ideensammlung. Nichts hier ist eine Zusage, und die Reihenfolge ist keine
Priorisierung.

| Datei | Inhalt |
| --- | --- |
| [FEATURES.md](./FEATURES.md) | Features im Plugin selbst — Anzeige, Bearbeitung, Zwischenablage |
| [CROSS-PLUGIN.md](./CROSS-PLUGIN.md) | Kreuzfeatures mit den übrigen `*.nvim`-Repos |
| [TERMINALS.md](./TERMINALS.md) | Protokolle, Backends, Terminal-Erkennung |

## Bereits umgesetzt

Damit die Listen unten nicht mit Erledigtem vermischt werden:

- Anzeige über OSC 1337 mit Cursor-Positionierung (`:Image`, `:Image show`)
- Galerie mehrerer Bilder im Raster (`:Image gallery [columns]`)
- Auswahl über das UI-Kit aus lib.nvim, Fallback `vim.ui.select` (`:Image list`)
- Navigation durch die Bilder eines Buffers (`:Image next` / `prev`)
- Metadaten via ImageMagick, optional (`:Image info`)
- Zwischenablage → Datei + Link (`:Image paste`)
- Anzeige festhalten (`:Image pin`)
- Doppelklick auf einen Markdown-Link
- Backend in `filetree.nvim`, Handler `:Open image` in `open.nvim`

## Leitplanken

Drei Entscheidungen, die bei jedem neuen Feature gelten sollen:

**Kein ImageMagick als Pflicht.** WezTerm dekodiert PNG/JPEG/GIF/WebP selbst.
ImageMagick darf Features *verbessern* (`:Image info`), nie *ermöglichen* —
sonst ist das Plugin auf Windows wieder von einer Installation abhängig, die
erfahrungsgemäß der Grund ist, warum am Ende nichts funktioniert.

**Keine Zellmessung.** `width`/`height` in Zellen plus
`preserveAspectRatio=1` erledigt das Terminal. Sobald irgendwo Pixel gerechnet
werden, ist der Weg zurück zu `ioctl(TIOCGWINSZ)` offen — und genau daran
scheitert `snacks.image` unter Windows.

**Low-Level meldet nicht.** `terminal`, `gallery`, `info` geben `ok, err`
zurück und rufen nie `notify`. Nur `lua/images/init.lua` entscheidet, was den User
erreicht. Sonst doppeln sich Meldungen, sobald ein Modul aus zwei Richtungen
aufgerufen wird.
