# ROADMAP — images.nvim

Ideensammlung. Nichts hier ist eine Zusage, und die Reihenfolge ist keine
Priorisierung.

| Datei | Inhalt |
| --- | --- |
| [FEATURES.md](./FEATURES.md) | Features im Plugin selbst — Anzeige, Bearbeitung, Zwischenablage |
| [CROSS-PLUGIN.md](./CROSS-PLUGIN.md) | Kreuzfeatures mit den übrigen `*.nvim`-Repos |
| [TERMINALS.md](./TERMINALS.md) | Protokolle, Backends, Terminal-Erkennung |

## Bereits umgesetzt

Damit die Liste oben (FEATURES.md) nicht mit Erledigtem vermischt wird:

- Anzeige über OSC 1337 mit Cursor-Positionierung (`:Image`, `:Image show`)
- Galerie mehrerer Bilder im Raster (`:Image gallery [columns]`), auch über
  einen Range (`:'<,'>Image`, `:'<,'>Image gallery`)
- Auswahl über das UI-Kit aus lib.nvim, Fallback `vim.ui.select` (`:Image list`)
- Navigation durch die Bilder eines Buffers (`:Image next` / `prev`)
- Metadaten via ImageMagick, optional (`:Image info`)
- SVG-Anzeige über automatische PNG-Konvertierung, gecacht (`images.convert`)
- Remote-Bilder für `:Image show`/Hover, gecacht, default aus
  (`display.remote`, `images.remote`) — gallery/compare/pickers/zen noch nicht
- Zwischenablage → Datei + Link (`:Image paste`), optional mit Alt-Text- und
  Dateinamen-Abfrage (`paste.ask_alt_text`, `paste.ask_filename`)
- Interaktiver Screenshot statt Zwischenablage-Umweg (`:Image screenshot`,
  `images.screenshot`), asynchron auf allen drei Plattformen — der
  Windows-Weg (Zwischenablage-Polling nach `ms-screenclip:`) ist die
  unsicherste der drei Implementierungen, siehe Moduldoc
- Bild ersetzen, Link bleibt (`:Image replace`)
- Bild als PDF exportieren, neben der Quelldatei (`:Image export`,
  `images.convert.to_pdf`); braucht ImageMagick zwingend
- Verwaiste Bilder in `paste.dir` finden und mit Bestätigung löschen
  (`:Image orphans`)
- Dateisystem-weite Suche mit Live-Vorschau über `snacks.picker`, Soft-Dependency
  (`:Image pickers cfile|cwd|path`)
- Vergleichsmodus mit echter relativer Skalierung: kennt `images.info` beide
  Pixelmaße (ImageMagick), bekommt das kleinere Bild eine proportional
  kleinere, zentrierte Box statt seine Pane zu füllen — siehe `images.scale`
  und `lib.nvim.ui.kit.compare`'s `on_compare`-Hook, der dafür ergänzt wurde
  (`:Image compare cfile|cwd|path`)
- Große Einzelanzeige in einem echten, editierbaren Fenster statt eines
  Preview-Floats (`:Image zen`)
- Floating-Window statt Draw-over-text für `:Image show`/Hover, opt-in
  (`display.hover_mode = "float"`, `images.hover_float`) — dieselbe
  Fenster-dann-zeichnen-Technik wie `:Image zen`
- Anzeige festhalten (`:Image pin`)
- Statusline-Indikator (`require("images").statusline`)
- which-key-Gruppe für den `<leader>i`-Präfix, aus den konfigurierten Keys
  hergeleitet
- Doppelklick auf einen Markdown-Link
- Terminal-Fähigkeitsprüfung mit einmaliger Warnung, nie hartem Abbruch
  (`:Image check`, `display.assume_supported`)
- Backend in `filetree.nvim`, Handler `:Open image` in `open.nvim`

## Leitplanken

Drei Entscheidungen, die bei jedem neuen Feature gelten sollen:

**Kein ImageMagick als Pflicht — mit zwei bewussten Ausnahmen.** WezTerm
dekodiert PNG/JPEG/GIF/WebP/BMP selbst. ImageMagick darf Features
*verbessern* (`:Image info`, `:Image compare`s relative Skalierung), nie
*ermöglichen* — sonst ist das Plugin auf Windows wieder von einer
Installation abhängig, die erfahrungsgemäß der Grund ist, warum am Ende
nichts funktioniert. Die erste Ausnahme ist SVG: WezTerm kann es
grundsätzlich nicht dekodieren, es gibt also keinen Weg ohne Konvertierung.
Die zweite ist `:Image export`: eine PDF entsteht nur über `magick`, es gibt
keine Terminal-native Alternative. Beide melden eine klare Fehlermeldung statt
eines stillen Fehlschlags, wenn ImageMagick fehlt.

**Keine Zellmessung.** `width`/`height` in Zellen plus
`preserveAspectRatio=1` erledigt das Terminal. Sobald irgendwo Pixel gerechnet
werden, ist der Weg zurück zu `ioctl(TIOCGWINSZ)` offen — und genau daran
scheitert `snacks.image` unter Windows.

**Low-Level meldet nicht.** `terminal`, `gallery`, `info` geben `ok, err`
zurück und rufen nie `notify`. Nur `lua/images/init.lua` entscheidet, was den User
erreicht. Sonst doppeln sich Meldungen, sobald ein Modul aus zwei Richtungen
aufgerufen wird.
