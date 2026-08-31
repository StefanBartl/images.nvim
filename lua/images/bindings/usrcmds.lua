---@module 'images.bindings.usrcmds'
---@brief Registers `:Image [subcommand] [options?]` via lib.nvim's composer.
---@description
--- One verb with routes rather than a family of flat commands: `<Tab>`
--- completion, typed arguments and documentation generation all come from the
--- same spec and cannot drift apart.
---
--- Range: `range = true` sits on the verb, not on an individual route — the
--- composer logic only picks up the first `range` value it finds for the whole
--- spec (verb-wide or route-wide) anyway, so a mix would be misleading.
--- `ctx.range.range > 0` distinguishes a genuine ranged invocation
--- (`:'<,'>Image …`) from one without, where `line1`/`line2` would otherwise
--- point at the current line without that being the intent.

local M = {}

local composer = require("lib.nvim.bindings.usercmd.composer")

-- Like the built-in FILE (readable file, <Tab> file completion), but
-- additionally permitting an http(s) URL — for `:Image show <url>` with
-- `display.remote.enabled` on. Whether remote images are actually downloaded is
-- `images.remote`'s decision at runtime; the only point here is that a URL gets
-- past the argument at all, rather than being rejected in validation as "not a
-- readable file".
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

--- Whether `ctx.range` carries an actually specified range.
---@param ctx table
---@return boolean
local function has_range(ctx)
  return ctx.range ~= nil and ctx.range.range > 0
end

--- Register `:Image …`.
---@param cfg ImagesNvim.Config
---@return nil
function M.register(cfg)
  composer.verb(cfg.command, {
    desc = ":Image — show, compare and insert images in the terminal",
    range = true,

    -- Bare `:Image` shows the image under the cursor -- the most common case
    -- needs no subcommand. Given a range (`:'<,'>Image`) it becomes a gallery
    -- of the images inside it instead of a single display.
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
        desc = "Show an image (without a path: the one under the cursor); an http(s) URL too with display.remote.enabled",
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
        -- A range restricts the choice to the selection rather than the whole
        -- Buffer zu durchsuchen.
        desc = "List the images in the buffer (or in the selection) and show one",
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
        -- A range narrows this to the images inside it rather than every
        -- image in the buffer -- the same scoping `list` uses, but rendered
        -- straight as a gallery instead of offered as a choice.
        desc = "Show the buffer's (or the selection's) images side by side",
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
        desc = "Jump to the buffer's next image and show it",
        run = function()
          require("images").step(1)
        end,
      },

      {
        path = { "prev" },
        desc = "Jump to the buffer's previous image and show it",
        run = function()
          require("images").step(-1)
        end,
      },

      {
        path = { "info" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "An image's format, dimensions and size",
        run = function(ctx)
          require("images").info(ctx.args.path)
        end,
      },

      {
        path = { "paste" },
        args = { { name = "name", type = "STRING", optional = true } },
        desc = "Save an image from the clipboard and link it; with {name} named directly instead of the configured name prompt",
        run = function(ctx)
          require("images").paste(ctx.args.name)
        end,
      },

      {
        path = { "screenshot" },
        desc = "Capture a screen selection interactively, save it and link it",
        run = function()
          require("images").screenshot()
        end,
      },

      {
        path = { "replace" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Replace an existing image with the clipboard contents",
        run = function(ctx)
          require("images").replace(ctx.args.path)
        end,
      },

      {
        path = { "export" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Export an image as a PDF, next to the source file",
        run = function(ctx)
          require("images").export(ctx.args.path)
        end,
      },

      {
        path = { "ocr" },
        args = { { name = "path", type = "FILE", optional = true } },
        flags = {
          -- A flag rather than a second positional: `:Image ocr deu` would
          -- otherwise be indistinguishable from a file called "deu", and the
          -- language is the rarer of the two arguments anyway.
          { name = "lang", short = "l", type = "STRING" },
        },
        desc = "Read the text out of an image into a scratch buffer (tesseract); --lang=<code> overrides ocr.lang",
        run = function(ctx)
          require("images").ocr(ctx.args.path, { lang = ctx.flags.lang })
        end,
      },

      {
        path = { "redact" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Open an image in redaction mode: mark boxes and black them out, the original stays",
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
        desc = "Browse images below cfile/cwd/path (live preview with snacks.picker)",
        run = function(ctx)
          require("images").browse(ctx.args.scope, ctx.args.dir)
        end,
      },

      {
        path = { "orphans" },
        desc = "Find images in the target directory with no link, and optionally delete them",
        run = function()
          require("images").orphans()
        end,
      },

      {
        path = { "calibrate" },
        desc = "Measure this terminal's image placement (test card, nudged into place); the result is stored",
        run = function()
          require("images.calibrate").run()
        end,
      },

      {
        path = { "debug" },
        args = {
          { name = "mode", type = "STRING", enum = { "report", "columns", "float" } },
          { name = "path", type = "FILE", optional = true },
        },
        desc = "Measure image placement: report (log draws), columns (constant vs. scaling offset), float (is a window where it says it is)",
        run = function(ctx)
          local debug = require("images.debug")
          local mode = ctx.args.mode
          if mode == "columns" then
            debug.columns(ctx.args.path)
          elseif mode == "float" then
            debug.float(nil, nil, ctx.args.path)
          else
            debug.report()
          end
        end,
      },

      {
        path = { "compare" },
        args = {
          { name = "scope", type = "STRING", enum = { "cfile", "cwd", "path" }, optional = true },
          { name = "dir", type = "DIR", optional = true },
        },
        desc = "Pick two images below cfile/cwd/path and compare them side by side",
        run = function(ctx)
          require("images").compare(ctx.args.scope, ctx.args.dir)
        end,
      },

      {
        path = { "zen" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Show an image large, in an editable window (not a preview window)",
        run = function(ctx)
          require("images").zen(ctx.args.path)
        end,
      },

      {
        path = { "draw" },
        args = {
          { name = "position", type = "STRING", enum = require("images.scale").POSITIONS },
          { name = "path", type = "FILE", optional = true },
        },
        desc = "Draw an image at a named position in the current window (without a path: the one under the cursor)",
        run = function(ctx)
          require("images").draw(nil, ctx.args.position, ctx.args.path)
        end,
      },

      {
        path = { "pin" },
        desc = "Pin the display — no clearing on cursor movement",
        run = function()
          require("images").pin()
        end,
      },

      {
        path = { "check" },
        desc = "Check whether this terminal can display images",
        run = function()
          require("images").recheck()
        end,
      },

      {
        path = { "clear" },
        desc = "Remove the displayed images",
        run = function()
          require("images").clear()
        end,
      },
    },
  })
end

return M
