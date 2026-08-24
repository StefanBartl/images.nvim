---@module 'images.@types'
---@brief Typdefinitionen für images.nvim.

---@class ImagesNvim.Config
---@field command string Name des User-Commands (default "Image")
---@field extensions string[] Endungen, die als Bild gelten
---@field display ImagesNvim.DisplayConfig
---@field paste ImagesNvim.PasteConfig
---@field keymaps ImagesNvim.KeymapConfig
---@field deps_popup? boolean Einmaliges lib.nvim.deps-Popup beim ersten setup() nach Installation zeigen (default true; ohne lib.nvim.deps wirkungslos)
---@field menu? ImagesNvim.MenuConfig `images.integrations.menu` (nvzone/menu-Kontextmenü-Beitrag) an-/abschalten

---Abschalter für `images.integrations.menu`. images.nvim hat selbst keine
---nvzone/menu-Abhängigkeit; das steuert nur, ob M.items()/M.submenu()
---Einträge liefern.
---@class ImagesNvim.MenuConfig
---@field enable? boolean default true

---@class ImagesNvim.DisplayConfig
---@field max_cols integer Maximale Bildbreite in Terminalzellen
---@field max_rows integer Maximale Bildhöhe in Terminalzeilen
---@field gallery_gap integer Zellen Abstand zwischen Galerie-Kacheln
---@field cell_aspect number Pixel-Seitenverhältnis einer Zelle (Breite/Höhe); 0 = Annahme 0.5 aus images.scale, siehe images.cell
---@field draw_inset integer Sicherheitsmarge in Zellen rundum; 1 = tolerant gegen Sub-Zellen-Versatz (Default), 0 = bündig (siehe images.anchor)
---@field terminal_padding { row: integer, col: integer } Fester Zeilen-/Spaltenversatz in ganzen Zellen, Ausgleich für Terminals mit nicht zell-ausgerichtetem window_padding (siehe images.anchor)
---@field hover_mode "overlay"|"float" Wie `:Image show`/Hover anzeigt (nicht die Galerie)
---@field assume_supported boolean Terminal-Erkennung übergehen (nur die Warnung)
---@field clear_events string[] Autocmd-Events, die das Bild wieder entfernen
---@field browse_exclude string[] Verzeichnisnamen, die `:Image pickers` beim Scan überspringt
---@field zen ImagesNvim.ZenConfig Größe des `:Image zen`-Fensters
---@field remote ImagesNvim.RemoteConfig Remote-Bilder für `:Image show`/Hover
---@field screenshot ImagesNvim.ScreenshotConfig `:Image screenshot`, nur unter Windows relevant
---@field redact ImagesNvim.RedactConfig `:Image redact`
---@field ascii_fallback ImagesNvim.AsciiFallbackConfig Blockgrafik-Fallback für Terminals ohne OSC 1337

---@class ImagesNvim.ZenConfig
---@field width number Anteil der Editorbreite (0–1)
---@field height number Anteil der Editorhöhe (0–1)

---@class ImagesNvim.RedactConfig
---@field padding_cells integer Sicherheitsmarge um jede markierte Box, in Zellen (siehe images.scale.cell_box_to_pixels)

---@class ImagesNvim.AsciiFallbackConfig
---@field enabled boolean Bei nicht unterstütztem Terminal eine Blockgrafik statt der OSC-Sequenz zeichnen (braucht ImageMagick, siehe images.ascii)

---@class ImagesNvim.RemoteConfig
---@field enabled boolean http(s)-Bilder laden; default false (Datenschutz, siehe images.remote)
---@field timeout_ms integer Download-Timeout
---@field max_bytes integer Maximale Downloadgröße

---@class ImagesNvim.ScreenshotConfig
---@field windows_timeout_ms integer Wie lange auf ein neues Zwischenablage-Bild gewartet wird
---@field windows_poll_interval_ms integer Abstand zwischen zwei Prüfungen der Zwischenablage

---@class ImagesNvim.PasteConfig
---@field dir string Zielverzeichnis relativ zum Dokument ("" = daneben)
---@field existing_dir_names string[] Vorhandene Ordnernamen (case-insensitiv), die statt `dir` verwendet werden, falls im Dokumentverzeichnis vorhanden
---@field name_template string Dateiname; %s = Dokumentname, %d = Zeitstempel
---@field link_template string Einzufügender Text ohne Alt-Text; %s = relativer Pfad
---@field ask_alt_text boolean Vor dem Einfügen nach einem Alt-Text fragen
---@field alt_link_template string Einzufügender Text mit Alt-Text; %s %s = Alt-Text, relativer Pfad
---@field ask_filename boolean Vor dem Einfügen nach einem Dateinamen fragen (Endung immer .png)

--- Jeder Keymap-Eintrag akzeptiert `false` zum Abschalten.
---@class ImagesNvim.KeymapConfig
---@field show string|false Bild unter dem Cursor
---@field gallery string|false Alle Bilder des Buffers nebeneinander
---@field next string|false Nächstes Bild
---@field prev string|false Vorheriges Bild
---@field paste string|false Bild aus der Zwischenablage einfügen
---@field screenshot string|false Bildschirmausschnitt aufnehmen und einfügen
---@field double_click boolean Doppelklick auf einen Markdown-Link zeigt das Bild
---@field filetypes string[] Filetypes, in denen die Bindungen gesetzt werden

---@class ImagesNvim.Target
---@field raw string Ziel wie im Buffer geschrieben
---@field path string Aufgelöster absoluter Pfad, oder bei einer Remote-URL die URL selbst (noch nicht geladen)
---@field lnum integer 1-basierte Zeile, in der das Ziel steht

return {}
