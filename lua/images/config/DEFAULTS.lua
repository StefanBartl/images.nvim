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
    gallery_gap = 1,
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
  },

  paste = {
    -- Leerer String legt das Bild neben das Dokument. "assets" oder "img"
    -- sind die üblichen Alternativen; das Verzeichnis wird bei Bedarf angelegt.
    dir = "assets",
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
