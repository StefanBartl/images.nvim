-- TESTS/testing_config_spec.lua — the safety nets in .testing.lua stay armed.
--
-- A guard set to "warn" only prints a line in the report; the case (and CI) stays green. This suite
-- is clean under every guard, so every guard has to fail the case ("error"). A guard that was
-- loosened without a reason (`deprecation = "warn"` once was, against the comment right above it)
-- would let a deprecated API slip into lua/ or TESTS/ unnoticed. A deliberate exception needs its
-- own entry in `allowed_loose` below, with the reason.

---@param H table harness from TESTS/run.lua
return function(H)
  -- Repo root = the directory above TESTS/, found from this file's own path (the runner's cwd is not
  -- guaranteed to be the repo root).
  local source = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fs.normalize(vim.fn.fnamemodify(source, ":p:h:h"))
  local path = root .. "/.testing.lua"
  H.eq(vim.fn.filereadable(path), 1, ".testing.lua is readable next to TESTS/")

  local cfg = dofile(path)
  H.eq(type(cfg), "table", ".testing.lua returns a table")
  H.eq(type(cfg.guards), "table", ".testing.lua configures the guards")

  -- guard name -> reason it may stay below "error". Empty on purpose: nothing is exempt.
  ---@type table<string, string>
  local allowed_loose = {}

  -- Every guard of testing.nvim this suite is clean under must be listed and at "error".
  local expected = { "fs", "state", "scheduled_error", "prompt", "deprecation", "process_net" }
  for _, name in ipairs(expected) do
    if allowed_loose[name] == nil then H.eq(cfg.guards[name], "error", "guard '" .. name .. "' fails the case") end
  end

  -- A guard added later (or a typo'd one) must not sit at "warn"/"off" without a stated reason either.
  for name, level in pairs(cfg.guards) do
    if allowed_loose[name] == nil then H.eq(level, "error", "guard '" .. name .. "' is not loosened without a reason") end
  end
end
