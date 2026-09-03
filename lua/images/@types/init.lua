---@module 'images.@types'
---@brief Type definitions for images.nvim.

---@class ImagesNvim.Config : ImagesNvim.Opts
---@field command string name of the user command (default "Image")
---@field extensions string[] extensions treated as images
---@field display ImagesNvim.DisplayConfig
---@field paste ImagesNvim.PasteConfig
---@field ocr ImagesNvim.OcrConfig
---@field keymaps ImagesNvim.KeymapConfig
---@field deps_popup? boolean show the one-off lib.nvim.deps popup on the first setup() after installation (default true; a no-op without lib.nvim.deps)
---@field menu? ImagesNvim.MenuConfig enable/disable `images.integrations.menu` (its nvzone/menu context-menu contribution)
---@field pdf? ImagesNvim.PdfConfig PDF pages drawn as pictures, via pdfport.nvim (see images.pdf)

---Off switch for `images.integrations.menu`. images.nvim has no nvzone/menu
---dependency of its own; this only controls whether M.items()/M.submenu()
---return any entries.
---@class ImagesNvim.MenuConfig : ImagesNvim.MenuOpts
---@field enable? boolean default true

---PDF pages drawn as pictures (`images.pdf`). images.nvim has no pdfport.nvim
---dependency of its own; without pdfport or poppler's `pdftoppm` a PDF is not
---claimed at all, whatever this says.
---@class ImagesNvim.PdfConfig : ImagesNvim.PdfOpts
---@field enabled boolean default true
---@field page integer 1-based page to rasterize; default 1
---@field dpi integer rasterization resolution; default 120

---@class ImagesNvim.DisplayConfig : ImagesNvim.DisplayOpts
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
---@field gopath_fallback boolean resolve a plain filesystem path under the cursor (outside any Markdown link) via gopath.nvim's cursor resolver, when installed; default true, a no-op otherwise (see images.resolve)

---@class ImagesNvim.ZenConfig : ImagesNvim.ZenOpts
---@field width number fraction of the editor width (0-1)
---@field height number fraction of the editor height (0-1)

---@class ImagesNvim.RedactConfig : ImagesNvim.RedactOpts
---@field padding_cells integer safety margin around each marked box, in cells (see images.scale.cell_box_to_pixels)

---@class ImagesNvim.AsciiFallbackConfig : ImagesNvim.AsciiFallbackOpts
---@field enabled boolean draw block graphics instead of the OSC sequence on an unsupported terminal (needs ImageMagick, see images.ascii)

---@class ImagesNvim.RemoteConfig : ImagesNvim.RemoteOpts
---@field enabled boolean load http(s) images; default false (privacy, see images.remote)
---@field timeout_ms integer download timeout
---@field max_bytes integer maximum download size

---@class ImagesNvim.ScreenshotConfig : ImagesNvim.ScreenshotOpts
---@field windows_timeout_ms integer how long to wait for a new clipboard image
---@field windows_poll_interval_ms integer interval between two clipboard checks

---@class ImagesNvim.PasteConfig : ImagesNvim.PasteOpts
---@field dir string target directory relative to the document ("" = alongside it)
---@field existing_dir_names string[] existing folder names (case-insensitive) used instead of `dir` when present in the document's directory
---@field name_template string file name; %s = document name, %d = timestamp
---@field link_template string text to insert without alt text; %s = relative path
---@field ask_alt_text boolean ask for alt text before inserting
---@field alt_link_template string text to insert with alt text; %s %s = alt text, relative path
---@field ask_filename boolean ask for a file name before inserting (extension always forced to .png)

---@class ImagesNvim.OcrConfig : ImagesNvim.OcrOpts
---@field lang string tesseract language code passed to `-l`; several at once as tesseract writes them, e.g. "deu+eng" (see images.ocr)
---@field args string[] extra tesseract arguments, appended verbatim (e.g. { "--psm", "6" })
---@field bin string|nil absolute path to the tesseract binary; nil = PATH, then the usual Windows install directories

--- Every keymap entry accepts `false` to disable it.
---@class ImagesNvim.KeymapConfig : ImagesNvim.KeymapOpts
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

--- What `setup()` accepts: the shape of `ImagesNvim.Config` with every field
--- optional, nested tables included. The resolved `ImagesNvim.Config` stays
--- strict, so a partial call is legal without every read of
--- `cfg.display.max_width` becoming a nil check.
---@class ImagesNvim.Opts
---@field command?    string name of the user command (default "Image")
---@field extensions? string[] extensions treated as images
---@field display?    ImagesNvim.DisplayOpts
---@field paste?      ImagesNvim.PasteOpts
---@field ocr?        ImagesNvim.OcrOpts
---@field keymaps?    ImagesNvim.KeymapOpts
---@field deps_popup? boolean show the one-off lib.nvim.deps popup on the first setup() after installation (default true; a no-op without lib.nvim.deps)
---@field menu?       ImagesNvim.MenuOpts enable/disable `images.integrations.menu` (its nvzone/menu context-menu contribution)
---@field pdf?        ImagesNvim.PdfOpts PDF pages drawn as pictures, via pdfport.nvim (see images.pdf)

---@class ImagesNvim.MenuOpts
---@field enable? boolean default true

---@class ImagesNvim.PdfOpts
---@field enabled? boolean default true
---@field page? integer 1-based page to rasterize; default 1
---@field dpi? integer rasterization resolution; default 120

---@class ImagesNvim.DisplayOpts
---@field max_cols?           integer maximum image width in terminal cells
---@field max_rows?           integer maximum image height in terminal rows
---@field gallery_gap?        integer cells of spacing between gallery tiles
---@field cell_aspect?        number pixel aspect ratio of one cell (width/height); 0 = the 0.5 assumption from images.scale, see images.cell
---@field draw_inset?         integer safety margin in cells all round; 1 = tolerant of sub-cell offsets (default), 0 = flush (see images.anchor)
---@field terminal_padding?   { row: integer, col: integer } fixed row/column offset in whole cells, compensating terminals whose window_padding is not cell-aligned (see images.anchor)
---@field hover_mode?         "overlay"|"float" how `:Image show`/hover presents (not the gallery)
---@field assume_supported?   boolean skip terminal detection (affects the warning only)
---@field clear_events?       string[] autocmd events that remove the image again
---@field browse_exclude?     string[] directory names `:Image pickers` skips while scanning
---@field browse_max_entries? integer upper bound on entries that scan visits (default 20000); a safety net, not an error
---@field zen?                ImagesNvim.ZenOpts size of the `:Image zen` window
---@field remote?             ImagesNvim.RemoteOpts remote images for `:Image show`/hover
---@field screenshot?         ImagesNvim.ScreenshotOpts `:Image screenshot`, only relevant on Windows
---@field redact?             ImagesNvim.RedactOpts `:Image redact`
---@field ascii_fallback?     ImagesNvim.AsciiFallbackOpts block-graphics fallback for terminals without OSC 1337
---@field gopath_fallback?    boolean resolve a plain filesystem path under the cursor (outside any Markdown link) via gopath.nvim's cursor resolver, when installed; default true, a no-op otherwise (see images.resolve)

---@class ImagesNvim.ZenOpts
---@field width?  number fraction of the editor width (0-1)
---@field height? number fraction of the editor height (0-1)

---@class ImagesNvim.RedactOpts
---@field padding_cells? integer safety margin around each marked box, in cells (see images.scale.cell_box_to_pixels)

---@class ImagesNvim.AsciiFallbackOpts
---@field enabled? boolean draw block graphics instead of the OSC sequence on an unsupported terminal (needs ImageMagick, see images.ascii)

---@class ImagesNvim.RemoteOpts
---@field enabled?    boolean load http(s) images; default false (privacy, see images.remote)
---@field timeout_ms? integer download timeout
---@field max_bytes?  integer maximum download size

---@class ImagesNvim.ScreenshotOpts
---@field windows_timeout_ms?       integer how long to wait for a new clipboard image
---@field windows_poll_interval_ms? integer interval between two clipboard checks

---@class ImagesNvim.PasteOpts
---@field dir?                string target directory relative to the document ("" = alongside it)
---@field existing_dir_names? string[] existing folder names (case-insensitive) used instead of `dir` when present in the document's directory
---@field name_template?      string file name; %s = document name, %d = timestamp
---@field link_template?      string text to insert without alt text; %s = relative path
---@field ask_alt_text?       boolean ask for alt text before inserting
---@field alt_link_template?  string text to insert with alt text; %s %s = alt text, relative path
---@field ask_filename?       boolean ask for a file name before inserting (extension always forced to .png)

---@class ImagesNvim.OcrOpts
---@field lang? string tesseract language code passed to `-l`; several at once as tesseract writes them, e.g. "deu+eng" (see images.ocr)
---@field args? string[] extra tesseract arguments, appended verbatim (e.g. { "--psm", "6" })
---@field bin?  string absolute path to the tesseract binary; unset = PATH, then the usual Windows install directories

---@class ImagesNvim.KeymapOpts
---@field show?         string|false image under the cursor
---@field gallery?      string|false every image in the buffer, side by side
---@field next?         string|false next image
---@field prev?         string|false previous image
---@field paste?        string|false paste an image from the clipboard
---@field screenshot?   string|false take a screenshot and insert it
---@field double_click? boolean double-clicking a markdown link shows the image
---@field filetypes?    string[] filetypes the bindings are installed in
return {}
