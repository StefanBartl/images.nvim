-- luacheck configuration for images.nvim
std = "lua51"
cache = true

-- Neovim injects `vim` as a read-only global. `bit` is LuaJIT's bit library,
-- always present in Neovim but not part of the `lua51` std this file pins --
-- images/testcard.lua needs it for the hand-rolled PNG writer's CRC/Adler.
read_globals = { "vim", "bit" }

-- Line length is handled by stylua, not luacheck.
max_line_length = false

ignore = {
  "212/_.*", -- unused argument whose name starts with underscore
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- Test specs intentionally use partial config tables and globals from the harness.
files["TESTS/**"] = {
  ignore = { "631", "211" },
}
