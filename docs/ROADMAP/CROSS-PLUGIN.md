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

### `markdown.nvim`
Der Pfad-Resolver wird schon genutzt. Umgekehrt fehlt: in markdowns
Link-Übersicht die Bildlinks mit Vorschau statt nur als Text; und beim
Einfügen eines Bildlinks direkt `:Image paste` anbieten. `markdown.nvim` ist
FileType-scoped und images.nvim ebenfalls — die Kopplung wäre natürlich.

### `mdview.nvim`
Markdown-Vorschau ohne Bilder ist eine halbe Vorschau. Beim Rendern die
Bildlinks einsammeln und an den passenden Stellen zeichnen. Das ist der Fall,
der dem echten Inline-Rendering am nächsten kommt, ohne Unicode-Placeholders zu
brauchen — weil mdview die Zeilenpositionen seiner Ausgabe selbst kennt.

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

### `insights.nvim`
Projektanalyse erzeugt Graphen — Abhängigkeiten, Aufrufbäume, Symbolverteilung.
Als Graphviz nach PNG und dann inline gezeigt, statt eine Textbaum-Darstellung
zu erzwingen. Dasselbe gilt für `documentation.nvim`, dessen `:DocMap`-Ausgabe
sich ebenfalls als Graph lesen ließe.

### `diff.nvim`
Bild-Diff: zwei Bildversionen nebeneinander, mit gemeinsamer Skalierung. Die
Galerie-Aufteilung liegt vor, `diff.nvim` müsste nur erkennen, dass beide
Seiten Bilder sind und statt eines Text-Diffs die Anzeige aufrufen. Ein
Pixel-Differenzbild wäre der Ausbau davon (braucht ImageMagick, also optional).

---

## Mittel — sinnvoll, aber mit offenen Fragen

### `language.nvim`
OCR auf einem Bild, um Text zu extrahieren und dann zu übersetzen oder zu
prüfen. Für Screenshots von Fehlermeldungen in fremdsprachigen Systemen ein
realer Support-Fall. Offene Frage ist die OCR-Abhängigkeit (`tesseract`), die
unter Windows nicht selbstverständlich ist — nach der Leitplanke also

Feedback con mir: Verbesserung, nicht Voraussetzung. tesseract kann ich voraussetzen dass das installiert wird ansonsten fallback chain  oder nicht anbeten des featuresohne es je nachdem!

### `runtime-analysis.nvim`
Flamegraphs als Bild statt als Textbaum. Der Nutzen hängt daran, ob eine
Flamegraph-Grafik in Terminalzellen noch lesbar ist; bei 60x25 Zellen
vermutlich nur als grober Überblick, mit Zoom (siehe FEATURES.md) deutlich
besser.

Feedback von moir: Das stimt, aner ,an könnte ein normale simage erschafen undd dann im browser bzw mit mdciews.nvim aider  jedem anderen imafe app anseheen -> wäre trotzdem ei n cool er mehrwert. Außerdem i documentation.nvim kömnnte dies imahges aucch gezegt werden! (dort gibt esds bereits einen bereich für daten aus runtime-analysis.nvim)

### `github_stats.nvim`
Statistiken als Diagramm rendern statt als Zahlenkolonne. Setzt einen
Chart-Renderer voraus, den es noch nirgends gibt — der Aufwand liegt dort,
nicht bei der Anzeige.

### `fileops.nvim`
Bildoperationen als Dateioperationen: konvertieren, skalieren, optimieren.
Passt thematisch zu „one command, all operations", braucht aber ImageMagick
und würde images.nvim nur für die Vorschau des Ergebnisses nutzen.

Feedback: imagemagick kann vorausgesetz werden ansonsten fallback chain oder disable

### `sessions.nvim`
Angeheftete Bilder über einen Sitzungswechsel hinweg erhalten. Klein, aber nur
sinnvoll, wenn es mehrere gleichzeitig angeheftete Bilder gibt (siehe
FEATURES.md) — vorher lohnt der Zustand die Speicherung nicht.

Feedback: Entfernen / übersrpingen / nicht umsetzen

### `reposcope.nvim`
Beim Vorschauen eines GitHub-Repos dessen Social-Preview-Karte oder die
README-Bilder zeigen. Nett, aber der Nutzen ist gering gegenüber dem
Netzwerk-Aufwand — braucht zudem Remote-Bilder (siehe FEATURES.md).

Feedback: Testlauf amchen, wie sehr das die snapines mindert

### `buffer-ctx.nvim`
Fügt Pfade, Module, Zeitstempel und UUIDs ein. Ein Bildlink ist derselbe
Vorgang mit anderem Inhalt; `:Image paste` deckt es aber bereits ab. Sinnvoll
wäre höchstens ein gemeinsamer Einfüge-Mechanismus, keine neue Funktion.

Feedback: Entfernen / übersrpingen / nicht umsetzen

### `migrate.nvim`
Nutzt Telescope-Preview für alles über einzeilige Bereiche hinaus. Wenn ein
Migrationsschritt Bilddateien betrifft, wäre eine Vorschau statt Binärmüll
hilfreich — Randfall.

Feedback: Entfernen / übersrpingen / nicht umsetzen

---

## Kein sinnvoller Bezug

Vollständigkeitshalber, damit die Frage erledigt bleibt:

`cmdlog.nvim` (Kommandohistorie), `emojis.nvim` (Zeichenauswahl),
`gopath.nvim` (Navigation), `recommender.nvim` (Wiederholungsanalyse),
`replacer.nvim` (Suchen/Ersetzen), `spotlight.nvim` (Token in Logs),
`sandbox.nvim` (Container-TUI), `cascade.nvim` (Zeilen-Scan/Scope),
`lsp.nvim` und `dap.nvim`/`debugging.nvim` (Sprach- und Debug-Werkzeuge),
`migrate.nvim` über den genannten Randfall hinaus.

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
