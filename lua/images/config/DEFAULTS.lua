---@module 'images.config.DEFAULTS'
---@brief Default configuration for images.nvim.

---@type ImagesNvim.Config
return {
  command = "Image",

  -- svg is converted to PNG automatically before drawing (needs ImageMagick,
  -- see images.convert) -- WezTerm cannot decode SVG itself. Without
  -- ImageMagick you get a clear error instead of a silent failure.
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" },

  display = {
    -- Given in terminal cells, not pixels: OSC 1337 scales on its own,
    -- together with preserveAspectRatio. That removes the need to measure a
    -- cell -- the very point where snacks.image fails on Windows.
    max_cols = 60,
    max_rows = 25,
    -- Pixel aspect ratio of a terminal cell (width/height). 0 = use the 0.5
    -- assumption from images.scale. Affects how tightly the draw box sits
    -- around an image: too coarse a value leaves an empty strip below it.
    -- `:Image calibrate` measures this too now (alongside terminal_padding,
    -- in the same window) and stores it per machine -- setting it here
    -- overrides that measurement, same precedence as terminal_padding. It
    -- cannot be detected automatically either way, see images.cell.
    cell_aspect = 0,
    -- Margin in cells kept free all round when drawing. Default 1: the image
    -- sits centred with a little air rather than flush. The reason is
    -- robustness, not looks -- terminals whose window padding is not
    -- cell-aligned shift the image by a fraction of a cell, and drawn flush it
    -- then visibly spills past the frame (see images.anchor). This only
    -- absorbs the remainder: compensate a systematic, whole-cell offset via
    -- terminal_padding, not by growing the margin. 0 draws flush.
    draw_inset = 1,
    -- Fixed row/column offset when drawing, in whole terminal cells.
    -- Compensates terminals whose OSC 1337 placement does not account for
    -- their own window_padding (see images.anchor). `:Image calibrate`
    -- measures this for you and stores it; setting it here overrides that
    -- measurement. Default {0,0}: a plain no-op for any setup without this
    -- quirk.
    terminal_padding = { row = 0, col = 0 },
    gallery_gap = 1,
    -- "overlay" (default) draws over the text and disappears on cursor
    -- movement via repaint -- the behaviour proven since version 1. "float"
    -- opens a small unfocused window under the cursor instead (see
    -- images.hover_float). Affects only `:Image show`/hover, not the gallery.
    hover_mode = "overlay",
    -- Skip detection: set this when the terminal does speak OSC 1337 but is
    -- not recognised (`wezterm imgcat` works, images.nvim warns anyway). Only
    -- silences the warning, changes nothing about drawing.
    assume_supported = false,
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    -- Directory names `:Image pickers` skips while scanning, in addition to
    -- ".git", which is always excluded.
    browse_exclude = { ".deps", "node_modules" },
    -- Upper bound on entries visited by that scan. A safety net against a
    -- `cwd` that turns out to be the home directory, not an error: the
    -- results found so far are still shown.
    browse_max_entries = 20000,
    -- Size of the `:Image zen` window, as a fraction of the editor.
    zen = { width = 0.9, height = 0.85 },
    remote = {
      -- Off by default: hovering a remote image link should not fire a network
      -- request without consent -- the same principle as "load external
      -- images" in mail clients. See images.remote. Applies to `:Image show
      -- <url>`/hover only, not to gallery/compare/browse/zen, which do not
      -- support remote images yet.
      enabled = false,
      timeout_ms = 10000,
      max_bytes = 20 * 1024 * 1024,
    },
    -- Windows only, see images.screenshot: the one platform where `:Image
    -- screenshot` polls instead of waiting on the target file directly.
    screenshot = {
      windows_timeout_ms = 60000,
      windows_poll_interval_ms = 600,
    },
    -- `:Image redact`: safety margin around each marked box, in cells --
    -- better one cell too much blacked out than one too little, see
    -- images.scale.cell_box_to_pixels.
    redact = {
      padding_cells = 1,
    },
    -- Fallback for terminals without OSC 1337 (SSH, tmux without passthrough,
    -- an unrecognised terminal): coloured block graphics via extmarks instead
    -- of the OSC sequence, see images.ascii. Requires ImageMagick -- one of the
    -- deliberate exceptions to "ImageMagick improves, never enables", listed in
    -- docs/architecture.md. Single-image path only (`:Image show`/hover), same
    -- scope boundary as remote images.
    ascii_fallback = {
      enabled = true,
    },
    -- Soft dependency, opt-out: when the cursor sits over a plain filesystem
    -- path rather than a Markdown link (e.g. `docs/assets/screenshot.png`
    -- written as bare text) and gopath.nvim is installed, its cursor resolver
    -- is asked before falling back to Vim's own <cfile>. gopath.nvim already
    -- solves "what path is the cursor on" far more robustly (several base
    -- directories, existence confirmation, a whole-line fallback); this only
    -- consults it, images.nvim still does all the drawing. false disables the
    -- fallback outright, even with gopath.nvim installed. See images.resolve.
    gopath_fallback = true,
  },

  paste = {
    -- An empty string puts the image next to the document. "assets" or "img"
    -- are the usual alternatives; the directory is created when needed.
    dir = "assets",
    -- If the document's directory already holds a folder with one of these
    -- names (case-insensitive), that one is used instead of `dir` and no
    -- separate one (e.g. "assets") is created alongside it. An empty list
    -- disables the detection.
    existing_dir_names = { "Resources", "Ressourcen" },
    name_template = "%s-%d.png",
    link_template = "![](%s)",
    -- true asks for alt text before inserting (UI kit, otherwise
    -- vim.fn.input). Default false: the everyday case is screenshot -> one
    -- keypress -> done, without an interruption.
    ask_alt_text = false,
    alt_link_template = "![%s](%s)",
    -- true asks for a file name before inserting, prefilled with the template
    -- name; any path component entered is discarded and the extension is
    -- always forced to .png (see images.paste.sanitize_filename). Default
    -- false for the same reason as ask_alt_text.
    ask_filename = false,
  },

  -- `:Image ocr`, see images.ocr. Deliberately top-level rather than under
  -- `display`: reading text out of a file is not a display concern, and
  -- `display.redact`'s counter-example only sits there because its one option
  -- is measured in terminal cells.
  ocr = {
    -- Passed to tesseract's `-l`. "eng" because that is what the installer
    -- ships; further languages are a separate download ("deu", "fra", ...),
    -- and several at once are written the way tesseract wants them,
    -- "deu+eng". `:checkhealth images` lists what is actually installed.
    lang = "eng",
    -- Extra tesseract arguments, appended verbatim -- e.g. { "--psm", "6" }
    -- for a screenshot that is one uniform block of text rather than a page
    -- layout. Empty by default: tesseract's automatic page segmentation is
    -- right far more often than a fixed guess.
    args = {},
    -- Absolute path to the tesseract binary. nil = look on PATH, then in the
    -- usual Windows install directories -- the UB-Mannheim installer does not
    -- add itself to PATH, see images.ocr. Set this when it lives somewhere
    -- else entirely.
    bin = nil,
  },

  -- One-off "which CLI tools does this plugin want, and why" popup on the
  -- first setup() after installation (via lib.nvim.deps). false disables it
  -- for this plugin, right here in the setup() spec -- no vim.g needed. The
  -- tools themselves are declared in docs/install.json and explained in
  -- docs/installation.md.
  deps_popup = true,

  -- A PDF page drawn as a picture, wherever this plugin draws pictures for a
  -- host (today: images.integrations.picker, a foreign picker's preview
  -- window). The page is rasterized by pdfport.nvim through poppler's
  -- `pdftoppm` and cached in stdpath("cache")/images.nvim/pdf; see images.pdf.
  --
  -- With either piece missing, a PDF is simply not one of ours: the host keeps
  -- its own preview rather than getting an empty window. `enabled = false`
  -- says the same thing on a machine that has both.
  pdf = {
    enabled = true,
    -- Which page. There is no paging in a preview window -- the first page is
    -- what says "this is that document", which is the whole question a
    -- preview answers.
    page = 1,
    -- Rasterization resolution. 120 puts an A4 page at ~1000x1400 px, which
    -- is more than a preview window (a few hundred pixels across) can show,
    -- and about a third of the bytes of the 216 hover.nvim rasterizes a
    -- full-screen float at. Raise it if you read pages in a large preview.
    dpi = 120,
  },

  -- Right-click context menu (nvzone/menu, soft dependency; entries from
  -- images.integrations.menu). Automatically inactive without nvzone/menu
  -- installed -- this only controls whether M.items()/M.submenu() return any
  -- entries at all.
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
