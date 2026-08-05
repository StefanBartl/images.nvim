---@module 'images.bindings.usrcmds'
---@brief Registriert `:Image [subcommand] [options?]` über lib.nvim's composer.
---@description
--- Ein Verb mit Routen statt einer Familie flacher Commands: `<Tab>`-Completion,
--- typisierte Argumente und die Doku-Generierung kommen dadurch aus derselben
--- Spec und können nicht auseinanderlaufen.

local M = {}

local composer = require("lib.nvim.usercmd.composer")

--- `:Image …` registrieren.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  composer.verb(cfg.command, {
    desc = ":Image — Bilder im Terminal anzeigen, vergleichen und einfügen",

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
        path = { "gallery" },
        args = { { name = "columns", type = "NUMBER", optional = true } },
        desc = "Alle Bilder des Buffers nebeneinander zeigen",
        run = function(ctx)
          require("images").gallery(nil, tonumber(ctx.args.columns))
        end,
      },

      {
        path = { "next" },
        desc = "Zum nächsten Bild des Buffers springen und es zeigen",
        run = function()
          require("images").step(1)
        end,
      },

      {
        path = { "prev" },
        desc = "Zum vorherigen Bild des Buffers springen und es zeigen",
        run = function()
          require("images").step(-1)
        end,
      },

      {
        path = { "info" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Format, Abmessungen und Größe eines Bildes",
        run = function(ctx)
          require("images").info(ctx.args.path)
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
        path = { "pin" },
        desc = "Anzeige festhalten — kein Aufräumen bei Cursorbewegung",
        run = function()
          require("images").pin()
        end,
      },

      {
        path = { "check" },
        desc = "Prüfen, ob dieses Terminal Bilder darstellen kann",
        run = function()
          require("images").recheck()
        end,
      },

      {
        path = { "clear" },
        desc = "Angezeigte Bilder entfernen",
        run = function()
          require("images").clear()
        end,
      },
    },
  })
end

return M
