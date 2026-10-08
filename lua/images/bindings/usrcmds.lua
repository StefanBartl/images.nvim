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
local expand_path = require("lib.nvim.cross.fs.expand_path")

-- Like the built-in FILE (readable file, <Tab> file completion), but
-- additionally permitting an http(s) URL — for `:Image show <url>` with
-- `display.remote.enabled` on. Whether remote images are actually downloaded is
-- `images.remote`'s decision at runtime; the only point here is that a URL gets
-- past the argument at all, rather than being rejected in validation as "not a
-- readable file".
composer.register_type("IMAGE_TARGET", {
  -- The line lib.nvim's option float shows for the `[path]` of `:Image show`.
  desc = "Image file, or http(s) URL with display.remote.enabled",
  validate = function(raw)
    if require("images.remote").is_remote(raw) then return true, raw, nil end
    -- expand_path, not vim.fn.expand (SEC-34): `raw` is the raw
    -- `:Image show <target>` argument the user typed.
    local expanded = expand_path(raw)
    local p = vim.fn.fnamemodify(expanded, ":p")
    if vim.fn.filereadable(p) ~= 1 then return false, nil, ("'%s' is not a readable file or URL"):format(raw) end
    return true, expanded, nil
  end,
  complete = function(arg_lead)
    return vim.fn.getcompletion(arg_lead, "file")
  end,
})

-- The three scope words of `:Image pickers` and `:Image compare` (see `images.browse.roots`), with
-- the line the option float shows for each.
local SCOPE_DESC = {
  cwd = "Current working directory",
  cfile = "Folder of the current buffer's file",
  path = "The directory given next",
}

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
        -- A range restricts the choice to the selection rather than searching
        -- the whole buffer.
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
        args = {
          {
            name = "columns",
            type = "NUMBER",
            optional = true,
            desc = "Columns in the grid (default: picked from the image count)",
          },
        },
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
        -- `[mode] [name]`: the first word is a link-path mode when it is one of
        -- env|abs|rel|repos|absolute|relative (the same as `path=...`, shorter),
        -- otherwise it is the file name, exactly as before the mode words
        -- existed. A file literally named like a mode word: `:Image paste
        -- rel env` (mode, then name) or `name=` is not needed.
        args = {
          {
            name = "mode",
            type = "STRING",
            optional = true,
            values = { "env", "abs", "rel", "repos" },
            desc = "Link path style; any other first word is the file name",
            enum_desc = {
              env = "Rooted at an env variable such as $REPOS_DIR",
              abs = "Full path with forward slashes",
              rel = "Relative to the document",
              repos = "Relative to $REPOS_DIR",
            },
          },
          {
            name = "name",
            type = "STRING",
            optional = true,
            desc = "File name for the image, saved as .png (skips the name prompt)",
          },
        },
        -- Bare `key=value`, not a `--flag`: a path prefix is the common case
        -- (a custom one especially) and would just be noise behind a dash --
        -- see media.nvim's `:Media dashboard path=<dir>` for the same
        -- reasoning. `values` only seeds completion; any other string
        -- (a custom prefix) is still accepted, see images.paste.resolve_link_path.
        kv = {
          {
            key = "path",
            type = "STRING",
            values = { "relative", "absolute", "repos" },
            desc = "Link path style: relative, absolute, repos, env or a custom prefix",
            enum_desc = {
              relative = "Relative to the document",
              absolute = "Full path with forward slashes",
              repos = "Relative to $REPOS_DIR",
            },
          },
        },
        desc = "Save an image from the clipboard and link it: :Image paste [env|abs|rel|repos] [name]; with {name} named directly instead of the configured name prompt; the mode word (or path=relative|absolute|repos|env|<prefix>) picks the link path (default: paste.default_path_mode, asked interactively when that is false)",
        run = function(ctx)
          local first, second = ctx.args.mode, ctx.args.name
          local mode = (ctx.kv or {}).path
          local name = first
          if first and require("images.paste").MODE_WORDS[first] then
            mode = mode or first
            name = second
          end
          require("images").paste(name, nil, mode)
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
        path = { "scale" },
        args = {
          {
            name = "size",
            type = "STRING",
            values = { "50%", "25%", "800x600", "1280x", "x720" },
            desc = "New size: percent (50%) or pixels (800x600, 800x, x600)",
            enum_desc = {
              ["800x600"] = "Fit inside 800 x 600 px, keeping the ratio",
              ["1280x"] = "1280 px wide, the height follows",
              ["x720"] = "720 px high, the width follows",
            },
          },
          { name = "path", type = "FILE", optional = true },
        },
        desc = "Write a resized copy next to the source (photo.png -> photo.scaled.png); needs ImageMagick",
        run = function(ctx)
          require("images").scale(ctx.args.size, ctx.args.path)
        end,
      },

      {
        path = { "optimise" },
        args = { { name = "path", type = "FILE", optional = true } },
        flags = {
          {
            name = "quality",
            short = "q",
            type = "NUMBER",
            desc = "Quality 1-100 for lossy formats; default: the source's own",
          },
        },
        desc = "Write a smaller copy next to the source: metadata stripped, best compression (photo.png -> photo.optimised.png); needs ImageMagick",
        run = function(ctx)
          require("images").optimise(ctx.args.path, { quality = ctx.flags.quality })
        end,
      },

      {
        path = { "convert" },
        args = {
          -- The enum is computed at registration time from the configured
          -- extensions, the same way `:Image draw` takes its positions from
          -- images.scale -- so adding a display format adds a target here too.
          {
            name = "format",
            type = "STRING",
            enum = require("images.convert").target_formats(),
            desc = "Target format: pdf or one of the configured image types",
          },
          { name = "path", type = "FILE", optional = true },
        },
        desc = "Write a copy in another format, same stem (photo.jpg -> photo.png); `pdf` takes the same route as :Image export",
        run = function(ctx)
          require("images").convert(ctx.args.format, ctx.args.path)
        end,
      },

      {
        path = { "ocr" },
        args = { { name = "path", type = "FILE", optional = true } },
        flags = {
          -- A flag rather than a second positional: `:Image ocr deu` would
          -- otherwise be indistinguishable from a file called "deu", and the
          -- language is the rarer of the two arguments anyway.
          {
            name = "lang",
            short = "l",
            type = "STRING",
            desc = "Tesseract language code, e.g. deu; default: ocr.lang",
          },
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
          {
            name = "scope",
            type = "STRING",
            enum = { "cfile", "cwd", "path" },
            optional = true,
            desc = "Where to look for images (default: cwd)",
            enum_desc = SCOPE_DESC,
          },
          {
            name = "dir",
            type = "DIR",
            optional = true,
            desc = "Directory to search (only used with scope path)",
          },
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
          {
            name = "mode",
            type = "STRING",
            enum = { "report", "columns", "float", "disarm" },
            desc = "Which placement measurement to run",
            enum_desc = {
              report = "Record every draw; run again to print the log",
              columns = "Draw at four columns to tell offset from scale error",
              float = "Draw into a float, marked at its reported corner",
              disarm = "Undo report's instrumentation and drop its log",
            },
          },
          { name = "path", type = "FILE", optional = true },
        },
        desc = "Measure image placement: report (log draws), columns (constant vs. scaling offset), float (is a window where it says it is), disarm (undo report's instrumentation)",
        run = function(ctx)
          local debug = require("images.debug")
          local mode = ctx.args.mode
          if mode == "columns" then
            debug.columns(ctx.args.path)
          elseif mode == "float" then
            debug.float(nil, nil, ctx.args.path)
          elseif mode == "disarm" then
            debug.disarm()
          else
            debug.report()
          end
        end,
      },

      {
        path = { "compare" },
        args = {
          {
            name = "scope",
            type = "STRING",
            enum = { "cfile", "cwd", "path" },
            optional = true,
            desc = "Where to look for images (default: cwd)",
            enum_desc = SCOPE_DESC,
          },
          {
            name = "dir",
            type = "DIR",
            optional = true,
            desc = "Directory to search (only used with scope path)",
          },
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
          {
            name = "position",
            type = "STRING",
            enum = require("images.scale").POSITIONS,
            desc = "Where in the current window the image goes",
            enum_desc = { full = "Fill the whole window" },
          },
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
