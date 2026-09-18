-- TESTS/compare_spec.lua — `:Image compare`, only the safely testable part.
--
-- `M.open()`'s success path opens a real `ui.kit.compare` SEARCH->MARKED->
-- COMPARE flow and draws into it — that stays unchecked, like every draw path
-- in this suite (see redact_spec.lua/zen_spec.lua). What is testable, and
-- what matters here, is the guard in front of it: unlike `images.browse`
-- (`:Image list`, snacks first, `ui.kit.select`/`vim.ui.select` after) there
-- is no fallback UI for a two-image comparison, so a missing ui.nvim has to
-- degrade to a clean message rather than the uncaught `module 'ui.kit' not
-- found` error this used to raise (confirmed by reverting the fix locally:
-- `pcall(compare.open, ...)` came back `false` with exactly that error).
--
-- ui.nvim is not on this suite's runtimepath (see TESTS/run.lua's own
-- comment on why), which makes this environment the every-CI-run regression
-- case for free -- no stubbing required to exercise the missing-dependency
-- path for real.

---@param H table harness from TESTS/run.lua
return function(H)
  require("images.config").setup(nil)
  local compare = require("images.compare")

  H.ok(not pcall(require, "ui.kit"), "sanity: this suite runs without ui.nvim on the runtimepath")

  -- ── fewer than two images: a clean message, before ui.kit is ever touched ─
  H.tmpdir(function(dir)
    H.write(dir .. "/a.png", "x")
    local ok = pcall(compare.open, "path", dir)
    H.ok(ok, "with only one image, open() reports and returns rather than erroring")
  end)

  -- ── two or more images, ui.kit unavailable: no crash (the regression) ────
  H.tmpdir(function(dir)
    H.write(dir .. "/a.png", "x")
    H.write(dir .. "/b.png", "x")
    local ok, err = pcall(compare.open, "path", dir)
    H.ok(ok, "BUG (fixed): open() used to raise \"module 'ui.kit' not found\" here instead of degrading -- " .. tostring(err))
  end)

  -- ── an invalid root is still a clean message ──────────────────────────────
  local ok = pcall(compare.open, "path", "")
  H.ok(ok, "an empty path scope does not error either")
end
