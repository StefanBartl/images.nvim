# CROSS-PLUGIN — Kreuzfeatures mit den übrigen Repos

Durchgang durch alle `*.nvim`-Repos in `E:\repos` mit der Frage, wo eine
Bildanzeige echten Nutzen bringt. Sortiert nach Tragfähigkeit, nicht
alphabetisch. Plugins ohne sinnvollen Bezug stehen am Ende — mit Begründung,
damit die Frage nicht bei jedem Durchgang neu gestellt wird.

Durchgehendes Prinzip: images.nvim ist überall **Soft-Dependency** über
`pcall`. Fehlt es, fällt der Aufrufer auf sein bisheriges Verhalten zurück.
Kein Repo bekommt eine harte Abhängigkeit auf die Bildanzeige.

---

## Stark — konkreter Nutzen, überschaubarer Aufwand

### `color_my_ascii.nvim` — UMGESETZT, aber nicht wie hier ursprünglich gedacht
Der umgekehrte Weg: ein Bild **als ASCII-Art** rendern, wenn das Terminal kein
OSC 1337 kann — der universelle Fallback für jedes Terminal ohne
Grafikprotokoll, macht das Plugin auch auf SSH-Sessions und in tmux (ohne
passthrough) benutzbar.

Umgesetzt in `images.ascii` (`display.ascii_fallback`), **ohne** die hier
angedachte color_my_ascii-Abhängigkeit: color_my_ascii färbt Muster-basiert
bekannte ASCII-Zeichenklassen (Pfeile, Box-Drawing, …) gegen ein benanntes
Schema, eine Farbe pro Klasse — für echte Bildfarben wird aber eine beliebige
RGB-Farbe pro Zelle gebraucht, die aus den Pixeln selbst kommt. Das ist eine
andere Art Färbung, die color_my_ascii architektonisch nicht anbietet und
auch nicht anbieten will (es ist ein Syntax-Highlighter für Text, kein
Bild-Renderer). `images.ascii` geht deshalb direkt über `nvim_set_hl`/
Extmarks: ImageMagick sampelt das Bild auf die Zielzellenzahl herunter
(`-resize WxH! -alpha off -depth 8 RGB:-`), jede Zelle wird ein "█" mit
eigener Vordergrundfarbe — Truecolor-Blockgrafik wie bei chafa/viu, nicht
ein Helligkeits-Zeichensatz. Braucht ImageMagick zwingend (vierte
Ausnahme neben SVG/export/redact). Bisher nur der Einzelbild-Pfad
(`:Image show`/Hover), wie bei den Remote-Bildern.

### `markdown.nvim` — UMGESETZT
Der Pfad-Resolver wird schon genutzt. Umgekehrt umgesetzt: `:Markdown links
show` zeigt Bildlinks jetzt mit Live-Vorschau (über `snacks.picker` +
`images.browse.draw_in_window` — dieselbe Funktion, die `:Image pickers`
selbst für die Preview nutzt, kein neuer API-Aufwand hier); `:Markdown image
paste|screenshot` delegiert direkt an `:Image paste`/`:Image screenshot`.

**Nebenfund dabei:** `markdown.nvim` hatte für `mi` (Bild unter dem Cursor
öffnen) schon einen eigenen In-Neovim-Vorschau-Pfad — aber über
snacks.nvim/image.nvim, dieselben Kitty-only-Plugins, die auf diesem
Windows/WezTerm-Setup nie zeichnen. images.nvim ist jetzt dort als
bevorzugter dritter Provider eingehängt (`markdown.util.image_preview`),
snacks/image.nvim bleiben Fallback für Setups, wo die tatsächlich
funktionieren.

### `mdview.nvim` — UMGESETZT, aber die eigentliche Lücke war eine andere
Markdown-Vorschau ohne Bilder ist eine halbe Vorschau. Beim Rendern die
Bildlinks einsammeln und an den passenden Stellen zeichnen.

Beim Nachsehen zeigte sich: mdview rendert komplett anders als images.nvim —
kein Terminal-Overlay, sondern ein echter Browser-Tab über einen Go-Relay +
Rust/WASM-Renderer (`comrak`). Der WASM-Renderer erzeugte für
`![alt](bild.png)` schon immer korrektes `<img>`-HTML (belegt durch einen
bereits bestehenden, grünen Test) — "Bildlinks einsammeln und zeichnen" war
also nie die Lücke. Die echte Lücke: der einzige `http.FileServer` des
Relays zeigte auf das Client-Bundle, nie auf das Verzeichnis des gerade
angezeigten Dokuments, also lief ein relativer Bildpfad serverseitig ins
Leere — kaputtes Bild-Icon im Browser trotz korrektem HTML.

Neue, token-authentifizierte `GET /asset`-Route im Go-Relay, aufgelöst
relativ zu einem Verzeichnis, das ausschließlich vom vertrauenswürdigen
lokalen Neovim-Prozess kommt (nie vom Browser-Tab), mit
Pfad-Traversal-Schutz und einer Bild-Endungs-Allowlist. Client-seitig
schreibt `resolveLocalImages` relative `<img src>` nach jedem Render auf
diese Route um. Details, Tests: `mdview.nvim/docs/architecture.md`
("Local image assets"), `docs/Roadmap/Roadmap.md`.

### `pickers.nvim`
**Geprüft und bewusst nicht so gebaut.** `:Image pickers`/`:Image compare`
binden stattdessen direkt an `snacks.picker` (Soft-Dependency, siehe
`images.browse`s Moduldoc): `pickers.nvim`s Engine-Abstraktion vereinheitlicht
telescope/fzf-lua/snacks, hat aber keinen engine-übergreifenden Weg, eine
eigene Live-Vorschau über alle drei zu legen — nur snacks erlaubt eine
custom `preview`-Funktion pro Picker, und genau die Live-Vorschau ist der
Punkt des Features. Ohne snacks fällt `images.browse` auf eine einfache
Auswahl ohne Vorschau zurück, statt über `pickers.nvim` eine Vorschau
vorzutäuschen, die es dort nicht geben kann.

### `insights.nvim` — UMGESETZT, enger gefasst als ursprünglich gedacht
Projektanalyse erzeugt Graphen — Abhängigkeiten, Aufrufbäume, Symbolverteilung.
Als Graphviz nach PNG und dann inline gezeigt, statt eine Textbaum-Darstellung
zu erzwingen.

Beim Nachsehen zeigte sich: nur die Import/Require-Daten (`insights.imports`)
sind tatsächlich schon graphförmig — jeder Eintrag ist bereits eine Kante
("Datei importiert Modul"), nur nie als Graph gezeichnet. Aufrufbäume und
Symbolverteilung existieren als Daten nirgends in insights.nvim (`symbols`
ist eine flache, unkorrelierte Liste) — das wäre eine neue, deutlich größere
Analysefunktion, keine neue Ansicht auf Vorhandenes. Deshalb bewusst nur der
Abhängigkeitsgraph: `:Insights imports graph` (`insights.imports.graph`),
Graphviz-`digraph` über `dot -Tpng`, externe Module standardmäßig
ausgeblendet (`imports.graph.include_external`, sonst mehr Rauschen als
Struktur), Anzeige über `images.nvim` (Soft-Dependency).

`documentation.nvim`s `:DocMap`-Ausgabe bleibt offen — eigenes Repo, eigener
Umfang, nicht in diesem Durchgang.

### `diff.nvim` — UMGESETZT
Bild-Diff: zwei Bildversionen nebeneinander, mit gemeinsamer Skalierung. Die
Galerie-Aufteilung liegt vor, `diff.nvim` müsste nur erkennen, dass beide
Seiten Bilder sind und statt eines Text-Diffs die Anzeige aufrufen.

`diff.core.resolve` las bisher jede Datei bedingungslos über
`vim.fn.readfile` als Text — bei zwei Bilddateien also ein bedeutungsloser
Byte-"Diff", nicht mal ein Fehler. `lua/diff/features/image_compare.lua`
fängt genau diesen Fall ab: beide Seiten lesbare Raster-Bildpfade (SVG
bewusst ausgenommen, das ist Text und diffft als Text sinnvoll) →
`images.gallery({a, b}, 2)` statt Text-Diff. Ohne installiertes images.nvim
eine klare Warnung statt des bisherigen stillen Unsinns. **Keine relative
Skalierung** wie bei `:Image compare` — das bräuchte
`lib.nvim.ui.kit.compare`s Scan-und-Auswahl-Ablauf, um beide Bilder
gleichzeitig zu kennen, was hier nicht passt: `:Diff` hat die beiden
konkreten Pfade schon aus den eigenen Argumenten, `images.gallery` ist
also die richtige, bereits vorhandene Grundfunktion — kein neuer API-Aufwand
in images.nvim nötig.

Damit ist dieser Durchgang durch die "Stark"-Liste komplett.

---

## Mittel — sinnvoll, aber mit offenen Fragen

### `language.nvim`
OCR auf einem Bild, um Text zu extrahieren und dann zu übersetzen oder zu
prüfen. Für Screenshots von Fehlermeldungen in fremdsprachigen Systemen ein
realer Support-Fall.

**Entschieden:** `tesseract` wird als vorhanden vorausgesetzt (Windows
eingeschlossen) — Verbesserung, nicht Voraussetzung, dieselbe Haltung wie bei
ImageMagick sonst im Plugin. Fehlt es, greift eine Fallback-Chain oder das
Feature wird schlicht nicht angeboten, je nachdem was beim Bauen sinnvoller
ist — keine offene Frage mehr, nur noch ein Umsetzungsdetail.

### `runtime-analysis.nvim`
Flamegraphs als Bild statt als Textbaum. In 60x25 Terminalzellen vermutlich
nur ein grober Überblick — aber das Bild landet ohnehin als normale Datei auf
der Platte und lässt sich im Browser, mit `mdview.nvim` oder jeder anderen
Bild-App in voller Auflösung ansehen, mit Zoom (siehe FEATURES.md) also
weiterhin ein echter Mehrwert, nicht nur eine Terminal-Krücke.

**Ergänzt:** dieselbe Grafik gehört auch nach `documentation.nvim` — dort gibt
es bereits einen Bereich für Daten aus `runtime-analysis.nvim`, der heute nur
Text zeigt.

### `github_stats.nvim`
Statistiken als Diagramm rendern statt als Zahlenkolonne. Setzt einen
Chart-Renderer voraus, den es noch nirgends gibt — der Aufwand liegt dort,
nicht bei der Anzeige.

### `fileops.nvim`
Bildoperationen als Dateioperationen: konvertieren, skalieren, optimieren.
Passt thematisch zu „one command, all operations".

**Entschieden:** ImageMagick wird als vorhanden vorausgesetzt, wie bei
`tesseract` oben — fehlt es, Fallback-Chain oder Feature deaktivieren.

---

## Verworfen — geprüft, bewusst nicht umgesetzt

### `sessions.nvim`
Angeheftete Bilder über einen Sitzungswechsel hinweg erhalten.

**Entschieden: nicht umsetzen.** Sinnvoll nur, wenn es mehrere gleichzeitig
angeheftete Bilder gibt — der Zustand lohnt die Speicherung sonst nicht.

### `buffer-ctx.nvim`
Ein Bildlink als derselbe Einfüge-Vorgang wie Pfade/Module/Zeitstempel/UUIDs.

**Entschieden: nicht umsetzen.** `:Image paste` deckt den Fall bereits ab; ein
gemeinsamer Einfüge-Mechanismus wäre keine neue Funktion.

### `migrate.nvim`
Bildvorschau statt Binärmüll in der Telescope-Preview, wenn ein
Migrationsschritt Bilddateien betrifft.

**Entschieden: nicht umsetzen.** Reiner Randfall.

---

## Offen — braucht einen Testlauf vor der Entscheidung

### `reposcope.nvim`
Beim Vorschauen eines GitHub-Repos dessen Social-Preview-Karte oder die
README-Bilder zeigen. Nett, aber der Nutzen ist gering gegenüber dem
Netzwerk-Aufwand — braucht zudem Remote-Bilder (siehe FEATURES.md).

**Nächster Schritt:** Testlauf, wie stark das die Snappiness von `:Reposcope`
tatsächlich mindert, bevor gebaut wird — noch keine Entscheidung.

---

## Kein sinnvoller Bezug

Vollständigkeitshalber, damit die Frage erledigt bleibt:

`cmdlog.nvim` (Kommandohistorie), `emojis.nvim` (Zeichenauswahl),
`gopath.nvim` (Navigation), `recommender.nvim` (Wiederholungsanalyse),
`replacer.nvim` (Suchen/Ersetzen), `spotlight.nvim` (Token in Logs),
`sandbox.nvim` (Container-TUI), `cascade.nvim` (Zeilen-Scan/Scope),
`lsp.nvim` und `dap.nvim`/`debugging.nvim` (Sprach- und Debug-Werkzeuge).
`migrate.nvim`, `sessions.nvim` und `buffer-ctx.nvim` stehen mit Begründung
unter "Verworfen" oben.

Bei `dap.nvim`/`debugging.nvim` wäre höchstens denkbar, einen Screenshot des
Debug-Zustands für einen Fehlerbericht abzulegen — das ist aber `:Image paste`
und braucht keine Integration.

---

## `lib.nvim`

Kein Kreuzfeature, sondern die Frage, was nach oben gehört. Kandidaten:

- **Terminal-Fähigkeitserkennung** — welches Grafikprotokoll kann dieses
  Terminal? Das interessiert jedes Plugin, das etwas anderes als Text
  ausgeben will, und ist heute in `images.health` verstreut.
- **Die OSC-1337-Sequenz selbst**, falls ein zweites Plugin sie direkt braucht
  (`mdview.nvim` wäre der erste Kandidat). Solange nur images.nvim zeichnet,
  bleibt sie besser hier — ein Transfer nach lib.nvim ohne zweiten Nutzer
  erzeugt nur eine Abhängigkeit ohne Gegenwert.
- **Die Rasteraufteilung aus `gallery.lua`** ist bereits generisch (reine
  Rechnung ohne Terminalbezug) und überschneidet sich mit
  `lib.nvim.ui.kit.layout`. Vor einem Transfer prüfen, ob `layout.compute`
  den Fall nicht schon abdeckt und wenn ja dies implementieren.
