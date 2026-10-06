-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "images",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). "file" because setup() of the plugin and the
  -- specs leave autocmds, user commands and highlight groups behind (state guard).
  isolated = "file",
  -- Safety nets, all clean on this suite, so all fail the case.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "warn",
    process_net = "error",
  },
  guard_allow = {
    spawn = {
      -- The plugin shells out to ImageMagick (convert, crop, scale, identify) and the specs run it for real.
      "magick",
      -- ocr_spec.lua runs the real tesseract binary (the specs skip when it is absent).
      "tesseract",
    },
  },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "MAGICK_*" },
  -- menu_spec.lua returns without a single assertion when no ui.nvim checkout exists (CI, by design);
  -- the old runner let that pass.
  assertions = "warn",
}
