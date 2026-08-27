---@module 'images.@types'
---@brief Type definitions for images.nvim.

---@class ImagesNvim.Config
---@field command string name of the user command (default "Image")
---@field extensions string[] extensions treated as images
---@field display ImagesNvim.DisplayConfig
---@field paste ImagesNvim.PasteConfig
---@field keymaps ImagesNvim.KeymapConfig
---@field deps_popup? boolean show the one-off lib.nvim.deps popup on the first setup() after installation (default true; a no-op without lib.nvim.deps)
---@field menu? ImagesNvim.MenuConfig enable/disable `images.integrations.menu` (its nvzone/menu context-menu contribution)

---Off switch for `images.integrations.menu`. images.nvim has no nvzone/menu
---dependency of its own; this only controls whether M.items()/M.submenu()
---return any entries.
---@class ImagesNvim.MenuConfig
---@field enable? boolean default true

---@class ImagesNvim.DisplayConfig
---@field max_cols integer maximum image width in terminal cells
---@field max_rows integer maximum image height in terminal rows
---@field gallery_gap integer cells of spacing between gallery tiles
---@field cell_aspect number pixel aspect ratio of one cell (width/height); 0 = the 0.5 assumption from images.scale, see images.cell
---@field draw_inset integer safety margin in cells all round; 1 = tolerant of sub-cell offsets (default), 0 = flush (see images.anchor)
---@field terminal_padding { row: integer, col: integer } fixed row/column offset in whole cells, compensating terminals whose window_padding is not cell-aligned (see images.anchor)
---@field hover_mode "overlay"|"float" how `:Image show`/hover presents (not the gallery)
---@field assume_supported boolean skip terminal detection (affects the warning only)
---@field clear_events string[] autocmd events that remove the image again
---@field browse_exclude string[] directory names `:Image pickers` skips while scanning
---@field browse_max_entries integer upper bound on entries that scan visits (default 20000); a safety net, not an error
---@field zen ImagesNvim.ZenConfig size of the `:Image zen` window
---@field remote ImagesNvim.RemoteConfig remote images for `:Image show`/hover
---@field screenshot ImagesNvim.ScreenshotConfig `:Image screenshot`, only relevant on Windows
---@field redact ImagesNvim.RedactConfig `:Image redact`
---@field ascii_fallback ImagesNvim.AsciiFallbackConfig block-graphics fallback for terminals without OSC 1337

---@class ImagesNvim.ZenConfig
---@field width number fraction of the editor width (0-1)
---@field height number fraction of the editor height (0-1)

---@class ImagesNvim.RedactConfig
---@field padding_cells integer safety margin around each marked box, in cells (see images.scale.cell_box_to_pixels)

---@class ImagesNvim.AsciiFallbackConfig
---@field enabled boolean draw block graphics instead of the OSC sequence on an unsupported terminal (needs ImageMagick, see images.ascii)

---@class ImagesNvim.RemoteConfig
---@field enabled boolean load http(s) images; default false (privacy, see images.remote)
---@field timeout_ms integer download timeout
---@field max_bytes integer maximum download size

---@class ImagesNvim.ScreenshotConfig
---@field windows_timeout_ms integer how long to wait for a new clipboard image
---@field windows_poll_interval_ms integer interval between two clipboard checks

---@class ImagesNvim.PasteConfig
---@field dir string target directory relative to the document ("" = alongside it)
---@field existing_dir_names string[] existing folder names (case-insensitive) used instead of `dir` when present in the document's directory
---@field name_template string file name; %s = document name, %d = timestamp
---@field link_template string text to insert without alt text; %s = relative path
---@field ask_alt_text boolean ask for alt text before inserting
---@field alt_link_template string text to insert with alt text; %s %s = alt text, relative path
---@field ask_filename boolean ask for a file name before inserting (extension always forced to .png)

--- Every keymap entry accepts `false` to disable it.
---@class ImagesNvim.KeymapConfig
---@field show string|false image under the cursor
---@field gallery string|false every image in the buffer, side by side
---@field next string|false next image
---@field prev string|false previous image
---@field paste string|false paste an image from the clipboard
---@field screenshot string|false take a screenshot and insert it
---@field double_click boolean double-clicking a markdown link shows the image
---@field filetypes string[] filetypes the bindings are installed in

---@class ImagesNvim.Target
---@field raw string target as written in the buffer
---@field path string resolved absolute path, or the URL itself for a remote target (not yet downloaded)
---@field lnum integer 1-based line the target sits on

return {}
