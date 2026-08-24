---@module 'images.config.DEFAULTS'
---@brief Standardkonfiguration für images.nvim.

---@type ImagesNvim.Config
return {
  command = "Image",

  -- svg wird vor dem Zeichnen automatisch nach PNG konvertiert (braucht
  -- ImageMagick, siehe images.convert) — WezTerm kann SVG nicht selbst
  -- dekodieren. Ohne ImageMagick kommt eine klare Fehlermeldung statt eines
  -- stillen Fehlschlags.
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" },

  display = {
    -- Angaben in Terminalzellen, nicht in Pixeln: OSC 1337 skaliert selbst,
    -- zusammen mit preserveAspectRatio. Dadurch wird keine Zellmessung
    -- gebraucht — der Punkt, an dem snacks.image auf Windows scheitert.
    max_cols = 60,
    max_rows = 25,
    -- Pixel-Seitenverhältnis einer Terminalzelle (Breite/Höhe). 0 = die
    -- Annahme 0.5 aus images.scale verwenden. Wirkt sich darauf aus, wie eng
    -- die Zeichenbox um ein Bild sitzt: ein zu grober Wert lässt einen leeren
    -- Streifen unter dem Bild stehen. Selbst messen (Terminalbreite in Pixeln
    -- / Spalten, geteilt durch Zeilenhöhe) — automatisch geht es nicht, siehe
    -- images.cell und docs/ROADMAP/TERMINALS.md.
    cell_aspect = 0,
    -- Sicherheitsmarge in Zellen, die beim Zeichnen rundum frei bleibt.
    -- Default 1: das Bild sitzt mit etwas Luft im Rahmen statt bündig. Grund
    -- ist Robustheit, nicht Optik — Terminals mit nicht zell-ausgerichtetem
    -- Fenster-Padding verschieben das Bild um Bruchteile einer Zelle, und
    -- bündig gezeichnet ragt es dann sichtbar über den Rahmen (siehe
    -- images.anchor). 0 zeichnet bündig; sinnvoll, wenn cell_aspect und
    -- terminal_padding für das eigene Setup stimmen.
    draw_inset = 1,
    -- Fester Zeilen-/Spaltenversatz beim Zeichnen, in ganzen Terminalzellen.
    -- Ausgleich für Terminals, deren OSC-1337-Platzierung ihr eigenes
    -- window_padding nicht mitrechnet (siehe images.anchor). Nur relevant,
    -- wenn das Padding auf ein Zell-Vielfaches gelegt wurde — sonst bleibt
    -- ein Rest, den kein Zeilen-/Spaltenversatz auflösen kann. Default
    -- {0,0}: reines No-op für jedes Setup ohne diesen Sonderfall.
    terminal_padding = { row = 0, col = 0 },
    gallery_gap = 1,
    -- "overlay" (default) zeichnet über den Text, verschwindet bei
    -- Cursorbewegung per Repaint — das bewährte Verhalten seit Version 1.
    -- "float" öffnet stattdessen ein kleines, unfokussiertes Fenster unter
    -- dem Cursor (siehe images.hover_float). Betrifft nur `:Image show`/
    -- Hover, nicht die Galerie.
    hover_mode = "overlay",
    -- Erkennung übergehen: setzen, wenn das Terminal OSC 1337 kann, aber
    -- nicht erkannt wird (`wezterm imgcat` funktioniert, images.nvim warnt
    -- trotzdem). Schaltet nur die Warnung ab, ändert am Zeichnen nichts.
    assume_supported = false,
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    -- Verzeichnisnamen, die `:Image pickers` beim Scan überspringt, zusätzlich
    -- zum immer ausgeschlossenen ".git".
    browse_exclude = { ".deps", "node_modules" },
    -- Größe des `:Image zen`-Fensters, als Anteil der Editorgröße.
    zen = { width = 0.9, height = 0.85 },
    remote = {
      -- Standard AUS: ein Hover über einen Remote-Bild-Link soll nicht ohne
      -- Zustimmung eine Netzwerkanfrage auslösen — dasselbe Prinzip wie
      -- "externe Bilder laden" in E-Mail-Clients. Siehe images.remote.
      -- Gilt nur für `:Image show <url>`/Hover, nicht für gallery/compare/
      -- browse/zen — die unterstützen Remote-Bilder noch nicht.
      enabled = false,
      timeout_ms = 10000,
      max_bytes = 20 * 1024 * 1024,
    },
    -- Nur unter Windows relevant, siehe images.screenshot: die einzige
    -- Plattform, auf der `:Image screenshot` per Polling statt direkt auf
    -- die Zieldatei wartet.
    screenshot = {
      windows_timeout_ms = 60000,
      windows_poll_interval_ms = 600,
    },
    -- `:Image redact`: Sicherheitsmarge um jede markierte Box, in Zellen —
    -- lieber eine Zelle zu viel geschwärzt als eine zu wenig, siehe
    -- images.scale.cell_box_to_pixels.
    redact = {
      padding_cells = 1,
    },
    -- Fallback für Terminals ohne OSC 1337 (SSH, tmux ohne passthrough, ein
    -- nicht erkanntes Terminal): statt der OSC-Sequenz eine farbige
    -- Blockgrafik über Extmarks, siehe images.ascii. Braucht ImageMagick
    -- zwingend — vierte bewusste Ausnahme neben SVG/export/redact. Nur der
    -- Einzelbild-Pfad (`:Image show`/Hover), wie bei den Remote-Bildern.
    ascii_fallback = {
      enabled = true,
    },
  },

  paste = {
    -- Leerer String legt das Bild neben das Dokument. "assets" oder "img"
    -- sind die üblichen Alternativen; das Verzeichnis wird bei Bedarf angelegt.
    dir = "assets",
    -- Existiert im Dokumentverzeichnis bereits ein Ordner mit einem dieser
    -- Namen (case-insensitiv), wird dieser statt `dir` verwendet und es wird
    -- kein eigener (z.B. "assets") parallel dazu angelegt. Leere Liste
    -- schaltet die Erkennung ab.
    existing_dir_names = { "Resources", "Ressourcen" },
    name_template = "%s-%d.png",
    link_template = "![](%s)",
    -- true fragt vor dem Einfügen nach einem Alt-Text (UI-Kit, sonst
    -- vim.fn.input). Default false: der Alltagsfall ist Screenshot → ein
    -- Tastendruck → fertig, ohne Unterbrechung.
    ask_alt_text = false,
    alt_link_template = "![%s](%s)",
    -- true fragt vor dem Einfügen nach einem Dateinamen, vorbelegt mit dem
    -- Template-Namen; ein eingegebener Pfadanteil wird verworfen, die Endung
    -- immer auf .png erzwungen (siehe images.paste.sanitize_filename).
    -- Default false aus demselben Grund wie ask_alt_text.
    ask_filename = false,
  },

  -- Einmaliges "welche CLI-Tools will dieses Plugin, und warum"-Popup beim
  -- ersten setup() nach der Installation (via lib.nvim.deps). false schaltet
  -- es für dieses Plugin ab, direkt hier in der setup()-Spec — kein vim.g
  -- nötig. Siehe README "Optional external tools".
  deps_popup = true,

  -- Rechtsklick-Kontextmenü (nvzone/menu, weiche Abhängigkeit; Einträge aus
  -- images.integrations.menu). Ohne installiertes nvzone/menu automatisch
  -- aus -- steuert nur, ob M.items()/M.submenu() überhaupt Einträge liefern.
  menu = {
    enable = true,
  },

  keymaps = {
    show = "<leader>im",
    gallery = "<leader>ig",
    next = "<leader>in",
    prev = "<leader>ip",
    paste = "<leader>iv",
    screenshot = "<leader>is",
    double_click = true,
    filetypes = { "markdown", "vimwiki", "norg", "text" },
  },
}
