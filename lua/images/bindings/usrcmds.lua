---@module 'images.bindings.usrcmds'
---@brief Registriert `:Image [subcommand] [options?]` über lib.nvim's composer.

local M = {}

local composer = require("lib.nvim.usercmd.composer")

--- `:Image …` registrieren.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  composer.verb(cfg.command, {
    desc = ":Image — Bilder im Terminal anzeigen und einfügen",

    -- Bare `:Image` zeigt das Bild unter dem Cursor: der häufigste Fall
    -- braucht keinen Subcommand.
    default = function()
      require("images").hover()
    end,

    routes = {
      {
        path = { "show" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Bild anzeigen (ohne Pfad: das unter dem Cursor)",
        run = function(ctx)
          local images = require("images")
          if ctx.args.path then
            images.show(ctx.args.path)
          else
            images.hover()
          end
        end,
      },

      {
        path = { "list" },
        -- Range macht hier Sinn: `:'<,'>Image list` beschränkt die Auswahl auf
        -- die Selektion statt den ganzen Buffer zu durchsuchen.
        desc = "Bilder im Buffer (oder in der Selektion) auflisten und eines zeigen",
        run = function(ctx)
          local range = ctx.range or {}
          require("images").list(range.first, range.last)
        end,
      },

      {
        path = { "paste" },
        desc = "Bild aus der Zwischenablage speichern und verlinken",
        run = function()
          require("images").paste()
        end,
      },

      {
        path = { "clear" },
        desc = "Angezeigtes Bild entfernen",
        run = function()
          require("images").clear()
        end,
      },
    },
  })
end

return M
