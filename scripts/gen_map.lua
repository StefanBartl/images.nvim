---@module 'scripts.gen_map'
--- CLI entry point for images.nvim's module map.
---
---   nvim --headless -l scripts/gen_map.lua                    # regenerate
---   nvim --headless -l scripts/gen_map.lua --check            # verify, write nothing
---   nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
---   nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
---
--- Everything above the options table is copied verbatim from
--- documentation.nvim's `scripts/gen_map.lua`; see its docs/REUSE.md.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

--- Put a dependency on the runtimepath, if it is not already reachable.
---
--- A headless `nvim -l` run starts with no plugin manager, so nothing beyond
--- `root` is on the rtp — `documentation` and `lib.nvim` both have to be found
--- by hand. Three candidates, in descending order of explicitness: an
--- environment variable (what CI sets), a `.deps/` checkout (what CI clones
--- into), and a sibling checkout (what a local development tree looks like).
---
--- Silent when the module already resolves, so a repository that *is* the
--- dependency — this one, for `documentation` — needs no special case.
---@param modname string A module the dependency provides, used as the probe.
---@param dirname string Repository directory name.
local function ensure(modname, dirname)
  if pcall(require, modname) then return end
  -- Built with explicit indices, not a `{a, b, c}` literal fed to `ipairs`:
  -- the environment-variable candidate is `nil` whenever it is unset — the
  -- normal case for CI, which relies on the `.deps/<dirname>` candidate
  -- below instead — and a table literal with `nil` in its first slot makes
  -- `ipairs` stop immediately without ever inspecting the slots after it,
  -- silently skipping every other candidate regardless of whether the
  -- directory actually exists.
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then candidates[#candidates + 1] = env_dir end
  candidates[#candidates + 1] = root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then return end
    end
  end
  io.stderr:write(("gen_map: %s not found (probed require('%s')).\n"):format(dirname, modname))
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(dirname:upper():gsub("[.-]", "_"), dirname)
  )
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")

local opts = require("documentation.config").build(root, {
  source = "lua/images",
  title = "images.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/StefanBartl/images.nvim",
  branch = "main",

  -- Two invariants that would otherwise rot in silence. Both are stated as
  -- guardrails in docs/ROADMAP/README.md; without a check they are a
  -- statement of intent in prose and nothing more.
  layers = {
    -- `terminal` takes sizes and positions as arguments and never looks them
    -- up itself. The moment it reads configuration, the layout decision moves
    -- into the drawing layer and stops being checkable without a terminal.
    {
      from = "images.terminal",
      to = "images.config",
      why = "the drawing layer takes sizes as arguments instead of reading configuration",
    },
    -- `gallery` is pure arithmetic: it returns placements and draws nothing.
    -- That is what keeps the grid layout testable without a terminal.
    {
      from = "images.gallery",
      to = "images.terminal",
      why = "the grid layout is pure arithmetic and does no drawing of its own",
    },
  },
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
