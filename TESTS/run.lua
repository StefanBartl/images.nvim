-- TESTS/run.lua — headless test runner for images.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile TESTS/run.lua" -c "qa!"
-- or:
--   nvim --headless -u NONE -l TESTS/run.lua
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero if any spec fails.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

-- The repo itself has to be on the runtimepath when invoked via `-l`, which
-- (unlike `-c "set rtp+=."`) does not add the cwd.
local repo = vim.fs.normalize(dir .. "..")
vim.opt.rtp:append(repo)
package.path = table.concat({
  repo .. "/lua/?.lua",
  repo .. "/lua/?/init.lua",
  package.path,
}, ";")

-- images.nvim depends on lib.nvim at runtime (notify, usercmd.composer, and
-- optionally the UI kit), so the suite needs it on the runtimepath.
--
-- A sibling checkout wins over the plugin-manager copy on purpose: the
-- bootstrap clone under stdpath("data")/lazy is frequently older than the
-- working checkout, and testing against a stale lib.nvim gives misleading
-- failures. `$LIB_NVIM_PATH` overrides both (useful in CI).
local function add_lib_nvim()
  local candidates = {}
  if vim.env.LIB_NVIM_PATH then candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH end
  candidates[#candidates + 1] = repo .. "/../lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    -- Normalize first: the sibling candidate contains a ".." segment and the
    -- stdpath one mixes separators on Windows; the runtimepath module searcher
    -- resolves neither, so an unnormalized entry silently finds nothing.
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:append(norm)
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      return norm
    end
  end
  return nil
end

if not add_lib_nvim() then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of images.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

-- Nur die seiteneffektfreien Module. Alles, was zeichnet, braucht ein
-- Terminal mit Grafikprotokoll und ist headless nicht pruefbar — genau
-- deshalb sind Rasteraufteilung, Linkerkennung und Metadaten von der
-- Zeichenschicht getrennt.
local specs = {
  "gallery_spec.lua",
  "resolve_spec.lua",
  "info_spec.lua",
  "config_spec.lua",
  "capability_spec.lua",
  "orphans_spec.lua",
  "keymaps_spec.lua",
  "usrcmds_spec.lua",
  "browse_spec.lua",
  "zen_spec.lua",
  "scale_spec.lua",
  "sanitize_filename_spec.lua",
  "convert_spec.lua",
  "remote_spec.lua",
  "screenshot_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    print(("ok    %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  print(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

print("\nIMAGES_TESTS_OK")
