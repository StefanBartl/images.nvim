---@module 'images.bindings.keymaps'
---@brief Keymaps für images.nvim — alle abschaltbar, alle which-key-fähig.
---@description
--- Alle Bindungen sind buffer-lokal und hängen an den Filetypes aus
--- `keymaps.filetypes`. Jede einzelne lässt sich über `false` deaktivieren
--- oder auf einen anderen Tastenweg legen; ein leerer `keymaps`-Block
--- registriert gar nichts.

local M = {}

--- Bindung → Aktion. Eine Tabelle statt fünf `if`-Blöcken, damit eine neue
--- Bindung nur hier einen Eintrag braucht.
---@type { option: string, desc: string, run: fun() }[]
local ACTIONS = {
  {
    option = "show",
    desc = "images: Bild unter dem Cursor anzeigen",
    run = function()
      require("images").hover()
    end,
  },
  {
    option = "gallery",
    desc = "images: alle Bilder des Buffers nebeneinander",
    run = function()
      require("images").gallery()
    end,
  },
  {
    option = "next",
    desc = "images: nächstes Bild",
    run = function()
      require("images").step(1)
    end,
  },
  {
    option = "prev",
    desc = "images: vorheriges Bild",
    run = function()
      require("images").step(-1)
    end,
  },
  {
    option = "paste",
    desc = "images: Bild aus der Zwischenablage einfügen",
    run = function()
      require("images").paste()
    end,
  },
}

--- Doppelklick auf einen Markdown-Link zeigt das Bild.
--- `<2-LeftMouse>` feuert nach dem regulären Klick, der Cursor steht also
--- bereits im Link — deshalb genügt `hover()` ohne eigene Positionsauswertung.
---@param buf integer
---@return nil
local function map_double_click(buf)
  vim.keymap.set("n", "<2-LeftMouse>", function()
    if not require("images").hover() then
      -- Kein Bildlink getroffen: Doppelklick soll sich normal verhalten
      -- (Wortauswahl), statt stumm geschluckt zu werden.
      vim.cmd("normal! viw")
    end
  end, { buffer = buf, desc = "images: Bild bei Doppelklick auf Link" })
end

--- Längstes gemeinsames Präfix der konfigurierten Bindungen, z.B. "<leader>i"
--- für "<leader>im"/"<leader>ig"/…. Ohne mindestens zwei Bindungen mit
--- gemeinsamem Anfang ist eine Gruppen-Beschriftung sinnlos.
---@param keys ImagesNvim.KeymapConfig
---@return string|nil
local function common_prefix(keys)
  local lhs_list = {}
  for _, action in ipairs(ACTIONS) do
    local lhs = keys[action.option]
    if type(lhs) == "string" and lhs ~= "" then lhs_list[#lhs_list + 1] = lhs end
  end
  if #lhs_list < 2 then return nil end

  local prefix = lhs_list[1]
  for i = 2, #lhs_list do
    local other = lhs_list[i]
    local n = math.min(#prefix, #other)
    while n > 0 and prefix:sub(1, n) ~= other:sub(1, n) do
      n = n - 1
    end
    prefix = prefix:sub(1, n)
    if prefix == "" then return nil end
  end
  -- Ein Präfix, das bereits eine vollständige Bindung ist, wäre als
  -- Gruppenname irreführend — which-key würde dann sowohl eine Aktion als
  -- auch eine Gruppe unter derselben Taste zeigen.
  for _, lhs in ipairs(lhs_list) do
    if lhs == prefix then return nil end
  end
  return prefix
end

--- Keymaps registrieren.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  local keys = cfg.keymaps or {}

  local prefix = common_prefix(keys)
  if prefix then require("images.bindings.which_key").setup(prefix) end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("images.keymaps", { clear = true }),
    pattern = keys.filetypes or { "markdown" },
    desc = "images: buffer-lokale Keymaps setzen",
    ---@param ev { buf: integer }
    callback = function(ev)
      if not vim.api.nvim_buf_is_valid(ev.buf) then return end
      for _, action in ipairs(ACTIONS) do
        local lhs = keys[action.option]
        if type(lhs) == "string" and lhs ~= "" then
          vim.keymap.set("n", lhs, action.run, { buffer = ev.buf, desc = action.desc })
        end
      end
      if keys.double_click then map_double_click(ev.buf) end
    end,
  })
end

return M
