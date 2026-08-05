---@module 'images.@types'
---@brief Typdefinitionen für images.nvim.

---@class ImagesNvim.Config
---@field command string Name des User-Commands (default "Image")
---@field extensions string[] Endungen, die als Bild gelten
---@field display ImagesNvim.DisplayConfig
---@field paste ImagesNvim.PasteConfig
---@field keymaps ImagesNvim.KeymapConfig

---@class ImagesNvim.DisplayConfig
---@field max_cols integer Maximale Bildbreite in Terminalzellen
---@field max_rows integer Maximale Bildhöhe in Terminalzeilen
---@field clear_events string[] Autocmd-Events, die das Bild wieder entfernen

---@class ImagesNvim.PasteConfig
---@field dir string Zielverzeichnis relativ zum Dokument ("" = daneben)
---@field name_template string Dateiname; %s = Dokumentname, %d = Zeitstempel
---@field link_template string Einzufügender Text; %s = relativer Pfad

---@class ImagesNvim.KeymapConfig
---@field show string|false Normal-Mode-Key für das Bild unter dem Cursor
---@field double_click boolean Doppelklick auf einen Markdown-Link zeigt das Bild
---@field filetypes string[] Filetypes, in denen die Bindungen gesetzt werden

---@class ImagesNvim.Target
---@field raw string Ziel wie im Buffer geschrieben
---@field path string Aufgelöster absoluter Pfad
---@field lnum integer 1-basierte Zeile, in der das Ziel steht

return {}
