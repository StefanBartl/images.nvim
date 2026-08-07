---@module 'images.bindings.usrcmds'
---@brief Registriert `:Image [subcommand] [options?]` über lib.nvim's composer.
---@description
--- Ein Verb mit Routen statt einer Familie flacher Commands: `<Tab>`-Completion,
--- typisierte Argumente und die Doku-Generierung kommen dadurch aus derselben
--- Spec und können nicht auseinanderlaufen.
---
--- Range: `range = true` steht am Verb, nicht an einer einzelnen Route — die
--- Composer-Logik übernimmt für die ganze Spec ohnehin nur den ersten
--- gefundenen `range`-Wert (verb- oder routenweit), ein Mix wäre also
--- irreführend. `ctx.range.range > 0` unterscheidet einen echten Aufruf mit
--- Bereich (`:'<,'>Image …`) von einem ohne, bei dem `line1`/`line2` sonst
--- auf die aktuelle Zeile zeigen würden, ohne dass das der Absicht entspricht.

local M = {}

local composer = require("lib.nvim.usercmd.composer")

-- Wie das eingebaute FILE (lesbare Datei, <Tab>-Dateivervollständigung),
-- aber zusätzlich eine http(s)-URL zulassend — für `:Image show <url>` bei
-- aktiviertem `display.remote.enabled`. Ob Remote-Bilder tatsächlich
-- geladen werden, entscheidet `images.remote` zur Laufzeit; hier geht es nur
-- darum, dass eine URL das Argument überhaupt passiert statt an der
-- Validierung als "keine lesbare Datei" abgewiesen zu werden.
composer.register_type("IMAGE_TARGET", {
  validate = function(raw)
    if require("images.remote").is_remote(raw) then return true, raw, nil end
    local expanded = vim.fn.expand(raw)
    local p = vim.fn.fnamemodify(expanded, ":p")
    if vim.fn.filereadable(p) ~= 1 then return false, nil, ("'%s' is not a readable file or URL"):format(raw) end
    return true, expanded, nil
  end,
  complete = function(arg_lead)
    return vim.fn.getcompletion(arg_lead, "file")
  end,
})

--- Ob `ctx.range` einen tatsächlich angegebenen Bereich trägt.
---@param ctx table
---@return boolean
local function has_range(ctx)
  return ctx.range ~= nil and ctx.range.range > 0
end

--- `:Image …` registrieren.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  composer.verb(cfg.command, {
    desc = ":Image — Bilder im Terminal anzeigen, vergleichen und einfügen",
    range = true,

    -- Bare `:Image` zeigt das Bild unter dem Cursor — der häufigste Fall
    -- braucht keinen Subcommand. Mit Bereich (`:'<,'>Image`) wird daraus eine
    -- Galerie der Bilder in diesem Bereich statt einer einzelnen Anzeige.
    default = function(ctx)
      local images = require("images")
      if has_range(ctx) then
        images.gallery_range(ctx.range.line1, ctx.range.line2)
      else
        images.hover()
      end
    end,

    routes = {
      {
        path = { "show" },
        args = { { name = "path", type = "IMAGE_TARGET", optional = true } },
        desc = "Bild anzeigen (ohne Pfad: das unter dem Cursor); auch eine http(s)-URL bei display.remote.enabled",
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
        -- Bereich beschränkt die Auswahl auf die Selektion statt den ganzen
        -- Buffer zu durchsuchen.
        desc = "Bilder im Buffer (oder in der Selektion) auflisten und eines zeigen",
        run = function(ctx)
          local images = require("images")
          if has_range(ctx) then
            images.list(ctx.range.line1, ctx.range.line2)
          else
            images.list(nil, nil)
          end
        end,
      },

      {
        path = { "gallery" },
        args = { { name = "columns", type = "NUMBER", optional = true } },
        -- Bereich zeigt nur die Bilder darin statt aller Bilder des Buffers —
        -- derselbe Bezug wie bei `list`, nur direkt als Galerie statt als
        -- Auswahl.
        desc = "Bilder des Buffers (oder der Selektion) nebeneinander zeigen",
        run = function(ctx)
          local images = require("images")
          local columns = tonumber(ctx.args.columns)
          if has_range(ctx) then
            images.gallery_range(ctx.range.line1, ctx.range.line2, columns)
          else
            images.gallery(nil, columns)
          end
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
        args = { { name = "name", type = "STRING", optional = true } },
        desc = "Bild aus der Zwischenablage speichern und verlinken; mit {name} direkt benannt statt der konfigurierten Namensabfrage",
        run = function(ctx)
          require("images").paste(ctx.args.name)
        end,
      },

      {
        path = { "screenshot" },
        desc = "Bildschirmausschnitt interaktiv aufnehmen, speichern und verlinken",
        run = function()
          require("images").screenshot()
        end,
      },

      {
        path = { "replace" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Bestehendes Bild durch den Zwischenablage-Inhalt ersetzen",
        run = function(ctx)
          require("images").replace(ctx.args.path)
        end,
      },

      {
        path = { "export" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Bild als PDF exportieren, neben der Quelldatei",
        run = function(ctx)
          require("images").export(ctx.args.path)
        end,
      },

      {
        path = { "redact" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Bild in einem Zensur-Modus öffnen: Boxen markieren und schwärzen, Original bleibt",
        run = function(ctx)
          require("images").redact(ctx.args.path)
        end,
      },

      {
        path = { "pickers" },
        args = {
          { name = "scope", type = "STRING", enum = { "cfile", "cwd", "path" }, optional = true },
          { name = "dir", type = "DIR", optional = true },
        },
        desc = "Bilder unterhalb cfile/cwd/path durchsuchen (Live-Vorschau mit snacks.picker)",
        run = function(ctx)
          require("images").browse(ctx.args.scope, ctx.args.dir)
        end,
      },

      {
        path = { "orphans" },
        desc = "Bilder im Zielverzeichnis ohne Link finden und ggf. löschen",
        run = function()
          require("images").orphans()
        end,
      },

      {
        path = { "compare" },
        args = {
          { name = "scope", type = "STRING", enum = { "cfile", "cwd", "path" }, optional = true },
          { name = "dir", type = "DIR", optional = true },
        },
        desc = "Zwei Bilder unterhalb cfile/cwd/path auswählen und nebeneinander vergleichen",
        run = function(ctx)
          require("images").compare(ctx.args.scope, ctx.args.dir)
        end,
      },

      {
        path = { "zen" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Bild groß anzeigen, in einem editierbaren Fenster (kein Preview-Fenster)",
        run = function(ctx)
          require("images").zen(ctx.args.path)
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
