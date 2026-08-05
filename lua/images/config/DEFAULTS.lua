---@module 'images.config.DEFAULTS'
---@brief Standardkonfiguration für images.nvim.

---@type ImagesNvim.Config
return {
  command = "Image",

  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp" },

  display = {
    -- Angaben in Terminalzellen, nicht in Pixeln: OSC 1337 skaliert selbst,
    -- zusammen mit preserveAspectRatio. Dadurch wird keine Zellmessung
    -- gebraucht — der Punkt, an dem snacks.image auf Windows scheitert.
    max_cols = 60,
    max_rows = 25,
    clear_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
  },

  paste = {
    -- Leerer String legt das Bild neben das Dokument. "assets" oder "img"
    -- sind die üblichen Alternativen; das Verzeichnis wird bei Bedarf angelegt.
    dir = "assets",
    name_template = "%s-%d.png",
    link_template = "![](%s)",
  },

  keymaps = {
    show = "<leader>im",
    double_click = true,
    filetypes = { "markdown", "vimwiki", "norg", "text" },
  },
}
