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
