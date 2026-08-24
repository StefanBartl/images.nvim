# TERMINALS — Protokolle, Backends, Erkennung

## Ausgangslage

Der Befund, auf dem dieses Plugin beruht, in Kurzform:

| Umgebung | Kitty-APC (`ESC _G`) | iTerm2-OSC-1337 |
| --- | --- | --- |
| pwsh in WezTerm/Windows | funktioniert | funktioniert |
| **nvim** in WezTerm/Windows | **nie gezeichnet** | funktioniert |

ConPTY ist nicht die Ursache — beide Protokolle passieren die Pipe
unbeschädigt, nachweisbar mit `wezterm imgcat`. Der Unterschied entsteht erst
durch Neovims Ausgabeschicht. Da `snacks.image` und `image.nvim` beide
ausschließlich Kitty-APC senden, sind sie dort unbrauchbar.

Zwei Fallstricke beim Nachmessen, die viel Zeit gekostet haben:

- OSC-Bilder bleiben stehen. Zwei Testphasen an **derselben** Position führen
  dazu, dass ein Restbild als Erfolg der zweiten Phase gelesen wird. Immer
  verschiedene Positionen verwenden.
- Der Terminalzustand ist relevant. Für belastbare Messungen WezTerm komplett
  neu starten, nicht nur einen neuen Tab öffnen.

## Platzierung: was gemessen wurde, und was daraus folgt

Ein Hover-Float zeichnet das Bild in ein Fenster, dessen Geometrie zugleich
die Zeichenbox ist. Dabei traten vier verschiedene Fehlbilder auf. Drei ließen
sich abstellen, eines ist eine Grenze des Protokolls. Die Messungen stammen
aus WezTerm `20240203-110809` auf Windows 11, Neovim 0.12.2, JetBrainsMono
Nerd Font 12pt — die abgeleiteten Regeln gelten allgemein, die konkreten
Zahlen nur für dieses Setup.

### 1. Bild sitzt an falscher Stelle, Statusline rutscht hoch

**Befund.** Die vier Teile der Sequenz (`ESC[s`, Positionierung, Payload,
`ESC[u`) gingen als vier getrennte `nvim_ui_send`-Aufrufe raus. Neovims
eigener TUI-Renderer schreibt in denselben tty-Strom und kann dazwischen
flushen; passiert das zwischen Positionierung und Payload, landet das Bild
dort, wo Neovims Cursor gerade steht.

**Regel.** Die vollständige Sequenz muss in **einem** `nvim_ui_send` rausgehen.
Umgesetzt in `images.terminal.sequence_for`.

### 2. Terminal scrollt, Neovims Grid wandert mit

**Befund.** OSC 1337 mit `inline=1` rückt den Cursor nach dem Bild um dessen
Höhe nach unten. Endet das Bild auf der letzten Zeile, scrollt dieser eine
Schritt den ganzen Schirm — Neovims Grid inklusive, ohne dass Neovim davon
erfährt. `ESC[u` stellt danach die Cursorposition wieder her, den Scroll nicht.

**Regel.** Zeichenbox auf den Schirm beschneiden, mit **einer Zeile
Sicherheitsabstand** für den Cursor-Vorschub. Umgesetzt in
`images.terminal.clamp_to_screen`.

### 3. Bild überlappt den Fensterrahmen

**Befund.** `nvim_win_get_position` liefert für ein gerahmtes und ein
rahmenloses Fenster mit identischer Konfiguration **denselben** Wert — die
Rahmen-Außenkante, nicht den Inhaltsanfang. Gegengeprüft mit `screenpos()`
bei angehängter UI:

| Rahmen | `screenpos(1,1)` relativ zu `pos + 1` |
| --- | --- |
| `none` | +0 Zeile / +0 Spalte |
| `rounded`, `single` | **+1 / +1** |
| nur oben | +1 / +0 |
| nur links | +0 / +1 |

`nvim_win_get_width`/`_height` sind davon **nicht** betroffen: sie melden
immer nur den Inhaltsbereich.

**Regel.** Pro Achse eine Zelle einrücken, sobald das jeweilige Rahmensegment
gesetzt ist. Umgesetzt in `images.anchor.border_inset`.

### 4. Bild sitzt Bruchteile einer Zelle daneben (nicht lösbar)

**Befund.** Isolationstests mit vollständigem WezTerm-Neustart zwischen jedem
Durchlauf:

| `window_padding` | `tab_bar_at_bottom` | Ergebnis |
| --- | --- | --- |
| `9/8/8/8` | `true` | Bild sichtbar zu tief, unten Überstand |
| `0/0/0/0` | `true` | **Bild exakt richtig** (Rest nur bei einem Seitenverhältnis) |
| `9/8/8/8` | `false` | vertikal richtig, dafür horizontal deutlich daneben |

Erste Ableitung: **`window_padding` ist die Ursache**, nicht die
Tab-Leisten-Position. Zweite Ableitung, aus der dritten Zeile: an
`tab_bar_at_bottom` zu drehen tauscht den Fehler nur gegen einen anderen —
kein Workaround, sondern eine Verschiebung.

**Warum das nicht wegzurechnen ist.** `CSI row;col H` positioniert
ausschließlich in **ganzen Zellen**; OSC 1337 kennt keinen Pixel-Offset. Ein
Padding, das kein glattes Vielfaches der Zellgröße ist (hier: 9 px links bei
rund 10 px Zellbreite), erzeugt einen Sub-Zellen-Versatz, den kein
Zeilen-/Spaltenwert auflösen kann — unabhängig davon, wie genau man das
Padding kennt.

**Was das Plugin daraus macht.** Weil ein Plugin diesen Versatz weder messen
noch erfragen kann, ist der Default **nicht** bündiges Zeichnen, sondern eine
Sicherheitsmarge von einer Zelle rundum (`display.draw_inset = 1`). Ein
Sub-Zellen-Versatz bleibt damit *innerhalb* des Rahmens statt sichtbar
darüber hinauszuragen — auf jedem Terminal, ohne Konfiguration und ohne
Erkennung. Das ist bewusst Robustheit vor Präzision: ein Bild, das mit etwas
Luft im Rahmen sitzt, liest sich als Absicht; eines, das asymmetrisch
übersteht, liest sich als Fehler.

**Für ein vermessenes Setup, in dieser Reihenfolge.**

1. `window_padding` auf **0** setzen. Einzige restlos saubere Variante.
2. Sonst `window_padding` auf ein **glattes Vielfaches der Zellgröße** legen —
   in WezTerm über die `cell`-Einheit (`"1cell"`) statt über Pixel. Achtung:
   nach eigener Messung bezieht sich `"1cell"` auf die Zell**breite**, auch
   für `top`/`bottom`; vertikal ist das also kein Vielfaches der Zellhöhe und
   der Versatz bleibt. Vertikal entweder `0` oder ein Pixelwert, der ein
   Vielfaches der Zellhöhe ist.
3. Verbleibt danach ein ganzzahliger Versatz, ihn über
   `display.terminal_padding = { row = …, col = … }` kompensieren und mit
   `display.draw_inset = 0` bündig zeichnen.

Dass genau dieselbe Mechanik in anderen Terminals mit eigenem Fensterrand
auftritt, ist zu erwarten; gemessen wurde sie nur in WezTerm.
`display.terminal_padding` ist deshalb terminal-neutral formuliert und
standardmäßig `{ row = 0, col = 0 }`, also ein reines No-op.

### Was aus Neovim heraus grundsätzlich nicht geht

Zur Zellgröße gibt es die Abfrage `CSI 16 t`, beantwortet mit
`CSI 6 ; <höhe> ; <breite> t`. **Diese Antwort erreicht ein Plugin nie:**
`:h TermResponse` nennt ausdrücklich nur **DA1-, OSC-, DCS- und
APC**-Antworten, und `CSI 6 ; … t` ist eine schlichte CSI-Antwort.
`nvim_list_uis()` liefert ebenfalls nur Zellmaße, keine Pixel — mit
angehängter UI geprüft.

Damit gibt es **keinen** Weg, Zellgröße oder Fenster-Padding automatisch zu
ermitteln. Ein erster Anlauf über `CSI 16 t` + `TermResponse` wurde gebaut,
lief ins Leere und wurde wieder entfernt; `display.cell_aspect` und
`display.terminal_padding` sind bewusst manuelle Werte. Das ist auch der Grund,
warum die Leitplanke "keine Zellmessung" (siehe [README](./README.md)) steht:
nicht aus Aufwandsgründen, sondern weil es die Schnittstelle nicht hergibt.

Ausdrücklich **nicht** betroffen ist XTVERSION (`ESC [ > q`) aus dem Abschnitt
[Erkennung](#erkennung): dessen Antwort ist DCS und wird durchgereicht.

## Weitere Backends

- **Sixel** für Terminals, die es können, aber kein OSC 1337 (xterm mit
  `--enable-sixel-graphics`, mlterm, Windows Terminal ab 1.22). Zweitgrößte
  Reichweite nach OSC 1337.
- **Kitty-APC** für Kitty und Ghostty, wo es funktioniert. Dort gäbe es
  zusätzlich Unicode-Placeholders und damit **echtes Inline-Rendering im
  Textfluss** — das einzige, was dieses Plugin heute grundsätzlich nicht kann.
- **ASCII-Art** als universeller Fallback, siehe `color_my_ascii.nvim` in
  [CROSS-PLUGIN.md](./CROSS-PLUGIN.md).
- **Systemanwendung** als letzte Stufe. `open.nvim` macht das bereits; im
  Plugin selbst wäre es die ehrlichste Reaktion auf ein Terminal ohne jede
  Grafikfähigkeit.

## Erkennung

Heute rät `images.health` anhand von `TERM_PROGRAM` und `WEZTERM_*`. Besser
wäre eine echte Abfrage:

- `ESC [ > q` (XTVERSION) liefert Terminalname und Version über `TermResponse`.
  Dieser Weg funktioniert unter Windows nachweislich — `snacks.image` erkennt
  WezTerm damit korrekt, auch wenn es danach nichts zeichnet.
- Für Kitty gibt es eine Protokoll-eigene Abfrage; für OSC 1337 nicht, dort
  bliebe es bei einer Namensliste.

Solange nur ein Backend existiert, ist der Aufwand nicht gerechtfertigt: die
Erkennung würde nur bestimmen, ob eine Warnung erscheint. Mit einem zweiten
Backend wird sie zur Voraussetzung.

## tmux und SSH

- **tmux** braucht `set -g allow-passthrough on`, sonst verschluckt es die
  Sequenzen. Die Health-Prüfung warnt bereits, setzt es aber nicht — das wäre
  ein Eingriff in die Konfiguration des Users.
- **SSH** funktioniert grundsätzlich, weil die Bilddaten inline in der Sequenz
  stehen und nicht als Dateipfad. Bei großen Bildern wird die Übertragung
  spürbar; eine Vorab-Verkleinerung wäre hier der Fall, in dem ImageMagick
  echten Nutzen bringt.

## Literatur und Referenzen

- [iTerm2 Inline Images Protocol](https://iterm2.com/documentation-images.html)
  — die OSC-1337-`File=`-Sequenz, die dieses Plugin sendet, samt der Angabe von
  `width`/`height` in Zellen und `preserveAspectRatio`.
- [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  — das Protokoll von snacks.image und image.nvim, inklusive der
  Unicode-Placeholders, die für echtes Inline-Rendering nötig sind.
- [WezTerm — imgcat](https://wezfurlong.org/wezterm/imgcat.html) — welche
  Protokolle WezTerm implementiert; `wezterm imgcat` ist der schnellste Test,
  ob ein Terminal überhaupt Bilder kann.
- [Sixel Graphics](https://en.wikipedia.org/wiki/Sixel) — Hintergrund zum
  ältesten der drei Protokolle und seiner Verbreitung.
- [Neovim `nvim_ui_send()`](https://neovim.io/doc/user/api.html) — der
  Ausgabeweg, über den dieses Plugin schreibt; verfügbar ab API-Level 14.
