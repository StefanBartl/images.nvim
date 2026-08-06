# REDACT — Konzept: Zensur-Modus für Bilder

> **Status: implementiert** — `:Image redact`, siehe
> [README.md → Bereits umgesetzt](./README.md#bereits-umgesetzt) und
> `lua/images/redact.lua`. Dieses Dokument bleibt als Architektur-Begründung
> stehen (Kern der ursprünglichen Konzeptarbeit, §1/§2 unten stimmen mit dem
> tatsächlichen Code überein) — §3 der ersten Fassung ("offene technische
> Frage") ist durch eine bewusste Design-Entscheidung ersetzt, siehe §3 unten.

Ausgearbeitete Fassung von FEATURES.md → "Zuschneiden und Annotieren". Zwei
konkrete Anwendungsfälle haben den Rahmen enger gezogen als der ursprüngliche
Roadmap-Satz ("Pfeile, Kästen, Unkenntlichmachung") — hier steht nur noch
**Unkenntlichmachung** (schwarze Boxen über sensiblen Bereichen), nicht mehr
Pfeile/Freihand-Annotation. Auslöser: casedesk (`lua/bindings/usrcmds/case/`)
verwaltet pro Case einen `Ressources/`-Ordner mit Anhängen (Screenshots, Logs)
aus SAP-Support-Fällen — reale Kundendaten. Zwei Use Cases:

**A — Datenschutz vor KI-Übergabe.** casedesks `ki.lua` baut heute nur
Prompts aus Text (Activity Stream, Zwischenablage), ruft keine KI-API und
verschickt keine Dateien (siehe `casedesk/CONCEPT.md` §8i). Sobald der
geplante KI-Ausbau anfängt, Anhänge mit in die Analyse zu geben, braucht es
vorher eine Möglichkeit, Kundendaten/Firmennamen in Screenshots unkenntlich
zu machen, bevor irgendein Byte das Gerät verlässt.

**B — Dauerhaft zensierte Kopie.** Unabhängig von KI: ein Screenshot mit
sichtbaren Kundendaten soll als geschwärzte Kopie ablegbar sein, z. B. um ihn
in ein öffentliches Ticket oder eine Doku einzufügen. Original bleibt
unverändert — es entsteht eine neue Datei, wie `:Image paste`/`export` es
schon an anderer Stelle halten.

---

## 1. Die eigentliche Hürde: Terminal-Grafik kennt keine Pixel-Klicks

Ein über OSC 1337 gezeichnetes Bild ist für Neovim **nicht interaktiv** —
Maus- oder Cursor-Events im Terminal liefern immer eine **Zellkoordinate**
(Zeile/Spalte), nie eine Pixelkoordinate im Bild. Man kann also nicht "auf
das Bild klicken" und eine Bildkoordinate zurückbekommen, wie es ein
Bildbearbeitungsprogramm mit echtem Fenster könnte.

Das klingt nach einem Widerspruch zur Leitplanke "Keine Zellmessung" aus
`docs/ROADMAP/README.md` — ist es aber nicht. Diese Leitplanke verbietet,
sich auf eine **vom Terminal erfragte** Pixelgröße zu verlassen (`ioctl
TIOCGWINSZ` o. ä.) — genau das, woran `snacks.image` unter Windows scheitert.
Hier geht es um etwas anderes: eine **Rechnung mit bereits bekannten oder
bewusst angenommenen Werten** — der angeforderten Zeichenbox (Zellen, von
`images.redact` selbst bestimmt) und der echten Bildpixelgröße (von
ImageMagick, über `images.info.collect()`, das `width`/`height` schon vorher
lieferte). Kein `ioctl`, keine Terminalabfrage.

---

## 2. Architektur — wie umgesetzt

### 2.1 Auswahl in Zellen, über echten Visual-Mode

Die Redaktions-Box wird während der Auswahl komplett in Zellkoordinaten
gehalten — keine Pixelmathematik, solange der Nutzer noch auswählt:

- `:Image redact [path]` öffnet ein Fenster wie `:Image zen`
  (`lib.nvim.window.make_scratch`, Bild als Terminal-Overlay über dem
  Fenster), aber mit einem Buffer, der komplett mit Leerzeichen in
  Bildgröße gefüllt ist (`images.scale.fit_cells`, siehe §2.2) — jede Zelle
  ist ein echtes, adressierbares Zeichen.
- Statt eines selbstgebauten Marker-Systems: **echter Neovim-Visual-Mode**.
  `v`/`<C-v>` + Bewegung + `<CR>` (Buffer-lokales Mapping im Visual-Mode)
  markiert eine Box — `confirm_box()` liest `getpos("v")`/`getpos(".")`,
  normalisiert auf die vier Ecken, legt einen Extmark
  (`hl_group = "Visual"`) als Vorschau an und verlässt den Modus. Kein
  neues Eingabe-System, kein Reinventing von Cursor-Movement — Nutzer, die
  schon Vim können, kennen die Bedienung bereits.
- `u` entfernt die zuletzt markierte Box (Extmarks werden komplett neu
  gezeichnet, `redraw_boxes()`), `w` brennt und speichert, `q`/`<Esc>`
  (`nice_quit`, wie `:Image zen`) bricht ohne zu schreiben ab.
- Die Live-Vorschau ist reines Neovim-Highlighting über dem Fensterbereich —
  kein erneutes Zeichnen des Bildes pro Box, das Overlay liegt über der
  bereits gezeichneten Terminal-Grafik.

### 2.2 Letterboxing vermeiden statt Anker erraten

Die ursprüngliche erste Fassung dieses Dokuments wollte den Offset einer
`preserveAspectRatio=1`-Letterbox nachträglich erraten (§3 der ersten
Fassung, "Anker links-oben oder zentriert?"). Bei genauerem Hinsehen ist
das nicht die einzige unbekannte Größe: um zu wissen, wie viele Zellen das
Terminal tatsächlich mit dem Bild ausfüllt, müsste auch das Pixel-
Seitenverhältnis einer einzelnen Terminalzelle bekannt sein — und genau das
misst images.nvim nach der "keine Zellmessung"-Leitplanke bewusst nie.

Umgesetzte Lösung: **das Problem umgehen statt lösen.** `images.scale.
fit_cells(max_cols, max_rows, image_px)` wählt die angeforderte Zeichenbox
so, dass sie das Bildseitenverhältnis (ausgedrückt über eine angenommene,
dokumentierte Zellbreite/-höhe, `images.scale.CELL_ASPECT = 0.5` — eine
Zelle ist ungefähr doppelt so hoch wie breit, typisch für Monospace-
Schriften) von vornherein trifft. Damit hat `preserveAspectRatio=1` kaum
noch etwas zu letterboxen, und `images.scale.cell_box_to_pixels` rechnet
ohne Offset — direkt Zelle → Pixel, linear.

Der verbleibende Fehler (falls `CELL_ASPECT` für die tatsächliche Schrift
daneben liegt) wird nicht weggerechnet, sondern **absorbiert**: jede Box
wächst vor dem Brennen um eine konfigurierbare Sicherheitsmarge
(`display.redact.padding_cells`, Default 1 Zelle) nach außen, gedeckelt auf
die Zeichenbox bzw. die Bildmaße. Das kehrt die Fehlerrichtung um — eine
falsche Annahme führt zu einer *zu großen*, nie zu einer *zu kleinen*
Redaktion. Für den eigentlichen Zweck (Kundendaten unkenntlich machen) ist
das die richtige Seite, auf der ein Fehler liegen darf.

### 2.3 Brennen: eine ImageMagick-Zeile

```
magick original.png -fill black \
  -draw "rectangle x1,y1 x2,y2" -draw "rectangle x3,y3 x4,y4" … \
  original.redacted.png
```

`images.convert.M.redact(path, boxes)`, synchron über `vim.system():wait()`,
kein Cache — ein einmaliger Export, kein Zeichenpfad, dieselbe Form wie
`M.to_pdf`. Dritte bewusste Ausnahme von der "kein ImageMagick als Pflicht"-
Leitplanke, neben SVG-Anzeige und `:Image export` — ohne `magick` gibt es
keinen sinnvollen Fallback.

### 2.4 Original bleibt, neue Datei entsteht

`bild.png` → `bild.redacted.png` (Endung der Quelldatei erhalten, nicht
immer `.png`), analog zu `:Image export`s `bild.pdf`. Existiert die
Zieldatei bereits, wird sie überschrieben — dieselbe Haltung wie
`:Image export`/`replace`: images.nvim fragt bei Dateioperationen nicht
nach, es meldet das Ergebnis. Kein Markdown-Link-Umbiegen (anders ursprünglich
erwogen) — ein casedesk-Anhang in `Ressources/` hat ohnehin meist keinen
Link im Buffer, und für den Fall, in dem doch einer existiert, bleibt der
alte Link auf dem Original bestehen, was für Use Case B (Original weiter
im Ticket sichtbar halten, Kopie zusätzlich ablegen) ohnehin der richtige
Default ist.

---

## 3. Zwei offene, ehrlich benannte Unsicherheiten

Beide sind Kalibrierungsfragen, keine Architekturfragen — der Code
funktioniert unabhängig davon, wie sie ausgehen, nur die Genauigkeit
verändert sich:

- **`CELL_ASPECT = 0.5` ist eine Annahme, kein Messwert** — für WezTerm mit
  der tatsächlich benutzten Schriftart nicht empirisch verifiziert (siehe
  §2.2). Sollte sich in der Praxis zeigen, dass Boxen spürbar daneben
  liegen, ist der erste Hebel `display.redact.padding_cells` hochzusetzen,
  nicht der Code — die Sicherheitsmarge ist genau für diesen Fall gedacht.
- **Die interaktive Tastenlogik ist nicht automatisiert getestet** — sie
  braucht ein echtes Terminal mit OSC-1337-Unterstützung, um wirklich
  verifiziert zu werden (wie überall in dieser Suite bleibt "Zeichnen"
  ungeprüft, siehe TESTS/zen_spec.lua). Getestet sind die reine Geometrie
  (`images.scale.fit_cells`/`cell_box_to_pixels`, TESTS/scale_spec.lua) und
  das Brennen (`images.convert.redact`, TESTS/convert_spec.lua, mit
  echtem `magick`). Zusätzlich manuell end-to-end verifiziert: ein
  200x100-Testbild durch `fit_cells` → `cell_box_to_pixels` (Marge 1
  Zelle) → `convert.redact` geschickt, dann mit `magick identify -format
  "%[pixel:p{x,y}]"` einen Pixel innerhalb der markierten Box (schwarz)
  und einen außerhalb (unverändert weiß) geprüft — beide korrekt. Was
  dabei *nicht* geprüft wurde: ob eine reale `v`/`<C-v>` + `<CR>`-Auswahl
  in einem echten WezTerm-Fenster dieselben Zellkoordinaten liefert, die
  hier von Hand eingesetzt wurden.

---

## 4. Was das für casedesk (Use Case A) bedeutet

`ki.lua` hat aktuell **keinen** Code-Pfad, der eine Datei irgendwohin
schickt — nur Text aus der Zwischenablage (siehe `casedesk/CONCEPT.md`
§8i). Es gibt also noch nichts zu gaten. Sobald casedesk anfängt, Anhänge
aus `Ressources/` an eine KI zu übergeben, wäre der naheliegende Haken:

- Eine Namenskonvention/`.redacted.json`-Sidecar (analog `.case.json`) pro
  redigierter Datei — "wurde am X geprüft, Y Boxen gesetzt".
- casedesks zukünftige "an KI übergeben"-Route prüft vor dem Versand: gibt
  es zu diesem Anhang eine `*.redacted.*`-Version? Wenn nein, warnen oder
  blockieren, statt das Rohbild stillschweigend zu verschicken.

Das ist casedesks eigene Arbeit, nicht images.nvim — images.nvim liefert nur
das Werkzeug (`:Image redact`), die Durchsetzungsregel gehört in
`casedesk/ki.lua`, sobald dort überhaupt ein Versand-Pfad existiert. Siehe
Verweis in `casedesk/ROADMAP.md`.
